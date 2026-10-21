import collections
import datetime
import grp
import ipaddress
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import urllib.request
from email.message import EmailMessage


ROOT = Path('/var/lib/host-report')
PRIVATE = ROOT / 'private'


def stamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def read_json(path, default):
    try:
        return json.loads(path.read_text())
    except FileNotFoundError:
        return default


def atomic(path, value, mode=0o600, gid=0):
    fd, name = tempfile.mkstemp(prefix='.report-', dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as out:
            json.dump(value, out, ensure_ascii=True, allow_nan=False)
            out.write('\n')
            out.flush()
            os.fsync(out.fileno())
            os.fchmod(out.fileno(), mode)
            os.fchown(out.fileno(), -1, gid)
        os.replace(name, path)
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def run(args, timeout=45, allowed=(0,)):
    # Never include stderr or arbitrary command output in an exception/report.
    result = subprocess.run(args, capture_output=True, text=True,
                            errors='replace', timeout=timeout)
    if result.returncode not in allowed:
        raise RuntimeError(f'{args[0]} exited {result.returncode}')
    return result.stdout


def command_json(args, **kwargs):
    return json.loads(run(args, **kwargs))


def short(value, length=100):
    return re.sub(r'[\x00-\x1f\x7f]', '?', str(value))[:length]


def parsed_ip(value):
    value = value.strip('[]')
    candidates = [value, value.rstrip('.')]
    if value.endswith(':'):
        candidates.append(value[:-1])
    if '.' in value and ':' in value:
        candidates.append(value.rsplit(':', 1)[0])
    for candidate in candidates:
        try:
            return str(ipaddress.ip_address(candidate))
        except ValueError:
            continue
    raise ValueError('invalid IP')


def journal(checks, state, errors, now):
    results = {name: {'count': 0, 'failure': check['failure'],
                      'top_ips': [], 'examples': []}
               for name, check in checks.items()}
    if not checks:
        return results
    args = ['journalctl', '--no-pager', '-o', 'json', '--lines=50001',
            '--until', f'@{now:.6f}']
    if state.get('cursor'):
        args += ['--after-cursor', state['cursor']]
    else:
        args += ['--since', f'@{now - 900:.6f}']
    try:
        text = run(args, timeout=90)
    except (RuntimeError, subprocess.TimeoutExpired):
        # Vacuumed cursors cannot silently skip the missing collection
        # interval.
        errors.append('journal cursor unavailable; replaying last 15 minutes')
        text = run(args[:7] + ['--since', f'@{now - 900:.6f}'], timeout=90)
    lines = text.splitlines()
    if len(lines) > 50000:
        errors.append('journal truncated at 50000 entries')
    counters = {name: collections.Counter() for name in checks}
    compiled = {name: (re.compile(c['pattern']),
                       re.compile(c['ipPattern']) if c['ipPattern'] else None)
                for name, c in checks.items()}
    for line in lines:
        entry = json.loads(line)
        state['cursor'] = entry.get('__CURSOR', state.get('cursor'))
        message = entry.get('MESSAGE', '')
        if not isinstance(message, str):
            continue
        for name, check in checks.items():
            if check['units']:
                if entry.get('_SYSTEMD_UNIT') not in check['units']:
                    continue
            elif entry.get('SYSLOG_IDENTIFIER') != 'sudo':
                continue
            pattern, ip_pattern = compiled[name]
            match = pattern.search(message)
            if not match:
                continue
            result = results[name]
            result['count'] += 1
            example = {}
            for key, value in match.groupdict().items():
                if key in ('user', 'action', 'command') and value:
                    # sudo arguments often contain credentials: executable
                    # only.
                    example[key] = short(value, 80)
            if ip_pattern:
                address = ip_pattern.search(message)
                if address:
                    try:
                        ip = parsed_ip(address[1])
                        counters[name][ip] += 1
                        example['ip'] = ip
                    except ValueError:
                        pass
            if example and len(result['examples']) < 5:
                result['examples'].append(example)
    for name, counter in counters.items():
        results[name]['top_ips'] = counter.most_common(10)
    return results


def collect(cfg, state):
    now = time.time()
    errors = []
    report = {'schema': 1, 'host': cfg['host'], 'generated_at': stamp(),
              'interval_start': state.get('last_collection', now - 900),
              'errors': errors}

    def attempt(name, fn, default):
        try:
            return fn()
        except (OSError, ValueError, KeyError, RuntimeError,
                subprocess.TimeoutExpired) as exc:
            errors.append(f'{name}: {type(exc).__name__}')
            return default

    current = os.path.realpath('/run/current-system')
    booted = os.path.realpath('/run/booted-system')
    boot_changes = [name for name in ('kernel', 'initrd', 'kernel-modules')
                    if os.path.realpath(Path(current) / name)
                    != os.path.realpath(Path(booted) / name)]
    report['system'] = {
        'current': current, 'booted': booted,
        'configuration_changed_since_boot': current != booted,
        'reboot_required': bool(boot_changes),
        'changed_boot_artifacts': boot_changes}
    report['uptime_seconds'] = float(
        Path('/proc/uptime').read_text().split()[0])
    report['load'] = list(os.getloadavg())
    report['memory_kib'] = {
        key: int(value.split()[0]) for key, value in
        (line.split(':', 1) for line in
         Path('/proc/meminfo').read_text().splitlines())
        if key in ('MemTotal', 'MemAvailable', 'SwapTotal', 'SwapFree')}
    report['failed_units'] = attempt('systemctl', lambda: [
        row['unit'] for row in command_json(
            ['systemctl', '--failed', '--all', '--no-pager',
             '--output=json'])], [])
    report['containers'] = []
    if cfg['docker']:
        def docker():
            ids = run(['docker', 'ps', '-aq']).split()
            if not ids:
                return []
            # Do not retain Config/Env or health log output from inspect.
            return [{'name': short(item['Name']),
                     'state': item['State']['Status'],
                     'health': item['State'].get('Health', {}).get('Status')}
                    for item in command_json(['docker', 'inspect'] + ids)]
        report['containers'] = attempt('docker', docker, [])
    report['instances'] = []
    if cfg['incus']:
        report['instances'] = attempt('incus', lambda: [
            {'name': short(item['name']), 'state': item['status']}
            for item in command_json(['incus', '--force-local', 'list',
                                      '--format', 'json'])], [])
    report['disks'] = []
    report['btrfs'] = []
    mounts = attempt('findmnt', lambda: command_json([
        'findmnt', '--json', '--list', '--real', '--output',
        'TARGET,SOURCE,FSTYPE'])['filesystems'], [])
    for mount in mounts:
        target = mount['target']

        def disk():
            stat = os.statvfs(target)
            used = stat.f_blocks - stat.f_bfree
            total = used + stat.f_bavail
            return {'mount': target, 'source': mount['source'],
                    'fstype': mount['fstype'],
                    'percent': round(100 * used / total, 1) if total else 0}
        usage = attempt('disk ' + target, disk, None)
        if usage:
            report['disks'].append(usage)
        if mount['fstype'] == 'btrfs':
            stats = attempt('btrfs ' + target, lambda: run([
                'btrfs', 'device', 'stats', target]), '')
            report['btrfs'].append({'mount': target, 'counters': [
                {'device_stat': short(line.rsplit(' ', 1)[0]),
                 'value': int(line.split()[-1])}
                for line in stats.splitlines() if line.split()[-1].isdigit()]})
    report['smart'] = []
    devices = attempt('smart scan', lambda: command_json([
        'smartctl', '--scan', '--json']).get('devices', []), [])
    for device in devices:
        def health():
            data = command_json(['smartctl', '--json', '-H', '-d',
                                 device['type'], device['name']],
                                allowed=tuple(range(256)))
            return {'device': device['name'],
                    'passed': data.get('smart_status', {}).get('passed'),
                    'exit_status': data['smartctl']['exit_status']}
        status = attempt('smart health', health, None)
        if status:
            report['smart'].append(status)
    # Interface/peer dumps contain private/preshared keys.
    # Select public fields explicitly and never publish a dump or stderr.
    report['wireguard'] = attempt('wireguard', lambda: [
        {'interface': parts[0], 'public_key': parts[1],
         'allowed_ips': parts[4], 'last_handshake': int(parts[5])}
        for parts in (line.split('\t') for line in
                      run(['wg', 'show', 'all', 'dump']).splitlines())
        if len(parts) == 9], [])
    report['nft_dynamic_sets'] = []
    if cfg['nftables']:
        def nft_sets():
            sets = command_json(['nft', '-j', 'list', 'sets'])['nftables']
            result = []
            for entry in sets:
                item = entry.get('set', {})
                if 'dynamic' not in item.get('flags', []):
                    continue
                data = command_json([
                    'nft', '-j', 'list', 'set',
                    item['family'], item['table'], item['name']])
                count = sum(len(row.get('set', {}).get('elem', []))
                            for row in data['nftables'])
                result.append({'family': item['family'],
                               'table': item['table'],
                               'name': item['name'],
                               'elements': count})
            return result
        report['nft_dynamic_sets'] = attempt('nft', nft_sets, [])
    report['security'] = attempt('journal', lambda: journal(
        cfg['logChecks'], state, errors, now), {})
    history = [row for row in state.get('history', [])
               if row['at'] > now - 86400]
    history.append({'at': now, 'counts': {
        name: item['count'] for name, item in report['security'].items()}})
    # Bounded even when the unit is manually invoked repeatedly.
    state['history'] = history[-2048:]
    report['security_24h'] = dict(sum(
        (collections.Counter(row['counts']) for row in state['history']),
        collections.Counter()))
    state['last_collection'] = now
    return report


def problems(report, alert):
    found = {}
    host = report['host']

    def add(key, message):
        found[f'{host}/{key}'] = short(message, 500)

    age = time.time() - datetime.datetime.fromisoformat(
        report['generated_at']).timestamp()
    if age > alert['staleAfter'] or age < -300:
        add('stale', 'report stale or clock skew')
    for error in report['errors']:
        add('collection/' + error.split(':')[0], error)
    for unit in report['failed_units']:
        add('unit/' + unit, 'failed unit: ' + unit)
    for item in report['disks']:
        if item['percent'] >= alert['diskPercent']:
            add('disk/' + item['mount'],
                f"disk {item['mount']} {item['percent']}%")
    for item in report['btrfs']:
        if any(row['value'] for row in item['counters']):
            add('btrfs/' + item['mount'], 'btrfs errors: ' + item['mount'])
    for item in report['smart']:
        if item['passed'] is not True or item['exit_status'] != 0:
            add('smart/' + item['device'],
                f"SMART {item['device']}: {item['passed']}")
    for item in report['containers']:
        if item['state'] not in ('running',) or item['health'] == 'unhealthy':
            add('container/' + item['name'], f"container {item['name']}: "
                f"{item['state']}/{item['health']}")
    for item in report['instances']:
        # Guests may be stopped on purpose (Incus restores the last running
        # state); only abnormal states alert, Stopped stays in the report.
        if item['state'] not in ('Running', 'Stopped'):
            add('instance/' + item['name'],
                f"instance {item['name']}: {item['state']}")
    for name, item in report['security'].items():
        if item['failure'] and item['count'] >= alert['authFailures']:
            add('auth/' + name, f"{name}: {item['count']} failures; "
                f"IPs {item['top_ips']}")
    return found


def fetch_peer(name, url, cfg, mode, gid):
    # urllib's HTTP proxy environment and redirects must not widen this root
    # fetch.
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *args, **kwargs):
            return None
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}),
                                         NoRedirect())
    with opener.open(url, timeout=20) as response:
        body = response.read(4 * 1024 * 1024 + 1)
    if len(body) > 4 * 1024 * 1024:
        raise ValueError('oversize report')
    report = json.loads(body)
    if report['schema'] != 1 or report['host'] != name:
        raise ValueError('wrong host or schema')
    # Validate fields consumed by alerting before atomically replacing last
    # good data.
    problems(report, cfg['alert'])
    atomic(ROOT / (name + '.json'), report, mode, gid)
    return report


def deliver_pending(cfg, state):
    pending = state.get('pending_mail')
    if not pending:
        return
    args = [cfg['alert']['sendmail'], '-t', '-oi']
    if cfg['alert']['from']:
        args += ['-f', cfg['alert']['from']]
    subprocess.run(args, input=pending['message'].encode(),
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                   timeout=30, check=True)
    state['alert_problems'] = pending['problems']
    state['last_mail'] = time.time()
    del state['pending_mail']
    atomic(PRIVATE / 'state.json', state)


def notify(cfg, found, state):
    # Retry the outbox even if the transient problem has disappeared.
    deliver_pending(cfg, state)
    alert = cfg['alert']
    previous = state.get('alert_problems', {})
    new = found.keys() - previous.keys()
    resolved = previous.keys() - found.keys()
    elapsed = time.time() - state.get('last_mail', 0)
    repeat = found and elapsed >= alert['repeatInterval']
    if not (new or resolved or repeat):
        return
    msg = EmailMessage()
    msg['To'] = alert['to']
    msg['From'] = alert['from'] or f"root@{cfg['host']}"
    msg['Subject'] = (f"[host-report] {cfg['host']}: {len(found)} problems, "
                      f"{len(resolved)} resolved")
    lines = [f'{key}: {value}' for key, value in sorted(found.items())]
    lines += ['resolved: ' + key for key in sorted(resolved)]
    msg.set_content('\n'.join(lines) + '\n')
    state['pending_mail'] = {'message': msg.as_string(), 'problems': found}
    atomic(PRIVATE / 'state.json', state)
    deliver_pending(cfg, state)


def main():
    os.umask(0o077)
    cfg = json.loads(Path(sys.argv[1]).read_text())
    gid = grp.getgrnam(cfg['readerGroup']).gr_gid if cfg['readerGroup'] else 0
    mode = 0o640 if cfg['readerGroup'] else 0o600
    PRIVATE.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(PRIVATE, 0o700)
    state = read_json(PRIVATE / 'state.json', {})
    report = collect(cfg, state)
    found = problems(report, cfg['alert'])
    report['fetch'] = {}
    for name, peer in cfg['fetch'].items():
        try:
            remote = fetch_peer(name, peer['url'], cfg, mode, gid)
            found.update(problems(remote, cfg['alert']))
            report['fetch'][name] = {
                'ok': True, 'generated_at': remote['generated_at']}
        except (OSError, ValueError, KeyError, TypeError, RuntimeError):
            found[name + '/unreachable'] = (
                'remote fetch failed; retained last good report')
            report['fetch'][name] = {'ok': False}
            old = read_json(ROOT / (name + '.json'), None)
            if old:
                found.update(problems(old, cfg['alert']))
    report['problems'] = found
    atomic(ROOT / (cfg['host'] + '.json'), report, mode, gid)
    if cfg['publish']['enable']:
        atomic(Path('/var/lib/host-report-publish') / (cfg['host'] + '.json'),
               report, 0o644)
    # Persist cursors before trying mail: an MTA failure must not replay logs.
    atomic(PRIVATE / 'state.json', state)
    if cfg['alert']['enable']:
        notify(cfg, found, state)
        atomic(PRIVATE / 'state.json', state)


if __name__ == '__main__':
    main()
