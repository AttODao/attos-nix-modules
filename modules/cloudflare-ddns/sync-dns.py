#!/usr/bin/env python3
"""Sync declared Cloudflare records; only prune CNAMEs carrying our owner tag."""
import ipaddress
import json
import os
import re
import sys
from urllib.parse import urlencode, quote
from urllib.request import Request, urlopen


class Cloudflare:
    def __init__(self, token, zone):
        if not token or not re.fullmatch(r"[0-9a-fA-F]{32}", zone):
            raise ValueError("CLOUDFLARE_API_TOKEN and a valid CLOUDFLARE_ZONE_ID are required")
        self.token = token
        self.base = "https://api.cloudflare.com/client/v4/zones/" + quote(zone, safe="") + "/dns_records"

    def request(self, method, suffix="", query=None, payload=None):
        url = self.base + suffix
        if query:
            url += "?" + urlencode(query)
        request = Request(url, method=method, headers={
            "Authorization": "Bearer " + self.token,
            "Content-Type": "application/json",
        }, data=None if payload is None else json.dumps(payload).encode())
        try:
            with urlopen(request, timeout=30) as response:
                data = json.load(response)
        except Exception as error:
            # HTTP/header exceptions can include the Authorization value.
            raise RuntimeError("Cloudflare DNS request failed") from error
        if data.get("success") is not True:
            raise RuntimeError("Cloudflare refused the DNS operation")
        return data

    def records(self, **query):
        page = 1
        result = []
        while True:
            data = self.request("GET", query=dict(query, page=page, per_page=100))
            result.extend(data["result"])
            if page >= data.get("result_info", {}).get("total_pages", 1):
                return result
            page += 1

    def delete(self, record):
        self.request("DELETE", "/" + quote(record["id"], safe=""))

    def create(self, payload):
        self.request("POST", payload=payload)

    def update(self, record, payload):
        self.request("PUT", "/" + quote(record["id"], safe=""), payload=payload)


def valid_hostname(name):
    return isinstance(name, str) and len(name) <= 253 and "." in name and all(
        len(label) <= 63 and re.fullmatch(r"[a-z0-9](?:[a-z0-9-]*[a-z0-9])?", label)
        for label in name.split(".")
    )


def sync(api, config, ipv4=None):
    record_type = config["recordType"]
    names = config["records"]
    comment = config["comment"]
    ttl = config.get("ttl", 1)
    proxied = config.get("proxied", False)
    if record_type not in ("A", "CNAME") or not isinstance(names, list) or not all(map(valid_hostname, names)):
        raise ValueError("Expected A/CNAME records and valid fully qualified hostnames")
    if not isinstance(comment, str) or not comment or type(ttl) is not int or ttl < 1 or type(proxied) is not bool:
        raise ValueError("Expected an ownership comment, positive TTL and boolean proxied")
    if len(set(names)) != len(names):
        raise ValueError("Duplicate DNS record names")
    if record_type == "CNAME":
        content = config["target"]
        if not valid_hostname(content) or content in names:
            raise ValueError("CNAME target must be a different valid hostname")
    else:
        content = str(ipaddress.IPv4Address(ipv4))

    for name in names:
        current = api.records(name=name)
        # Validate before deleting any conflicting records for this hostname.
        if record_type == "CNAME" and any(record["type"] not in ("A", "AAAA", "CNAME") for record in current):
            raise ValueError("Refusing to replace non-address DNS records for " + name)
        conflicts = ("CNAME",) if record_type == "A" else ("A", "AAAA")
        conflicting = [record for record in current if record["type"] in conflicts]
        payload = dict(type=record_type, name=name, content=content, ttl=ttl, proxied=proxied, comment=comment)
        existing = [record for record in current if record["type"] == record_type]
        updates = [record for record in existing if any(record.get(key) != value for key, value in payload.items())]
        if conflicting:
            # Cloudflare's database transaction keeps the old records if replacement fails.
            # DNS propagation itself is not atomic.
            api.request("POST", "/batch", payload={
                "deletes": [{"id": record["id"]} for record in conflicting],
                "puts": [dict(payload, id=record["id"]) for record in updates],
                "posts": [] if existing else [payload],
            })
        else:
            if not existing:
                api.create(payload)
            for record in updates:
                api.update(record, payload)

    if record_type == "CNAME":
        for record in api.records(type="CNAME", content=content):
            if record.get("comment") == comment and record["name"] not in names:
                api.delete(record)


def main():
    with open(sys.argv[1], encoding="utf-8") as handle:
        config = json.load(handle)
    api = Cloudflare(os.environ.get("CLOUDFLARE_API_TOKEN", ""), os.environ.get("CLOUDFLARE_ZONE_ID", ""))
    ipv4 = None
    if config["recordType"] == "A":
        with urlopen("https://api.ipify.org", timeout=20) as response:
            ipv4 = response.read(64).decode().strip()
    sync(api, config, ipv4)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # Do not dump requests, response bodies or the authentication header.
        print("DNS sync failed: " + str(error), file=sys.stderr)
        sys.exit(1)
