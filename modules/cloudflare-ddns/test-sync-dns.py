#!/usr/bin/env python3
import copy
import importlib.util
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("sync_dns", Path(__file__).with_name("sync-dns.py"))
dns = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dns)


class API:
    def __init__(self, records=(), fail_batch=False):
        self.values = copy.deepcopy(list(records))
        self.calls = []
        self.fail_batch = fail_batch

    def records(self, **query):
        return [dict(record) for record in self.values if all(record.get(key) == value for key, value in query.items())]

    def create(self, payload):
        self.calls.append(("create", payload))
        self.values.append(dict(payload, id="created"))

    def update(self, record, payload):
        self.calls.append(("update", record["id"]))
        self.values = [dict(payload, id=item["id"]) if item["id"] == record["id"] else item for item in self.values]

    def delete(self, record):
        self.calls.append(("delete", record["id"]))
        self.values = [item for item in self.values if item["id"] != record["id"]]

    def request(self, method, suffix, payload):
        assert method == "POST" and suffix == "/batch"
        self.calls.append(("batch", payload))
        if self.fail_batch:
            raise RuntimeError("fake batch failure")
        deleted = {item["id"] for item in payload["deletes"]}
        updates = {item["id"]: item for item in payload["puts"]}
        staged = [updates.get(item["id"], item) for item in self.values if item["id"] not in deleted]
        staged.extend(dict(item, id="batched") for item in payload["posts"])
        self.values = staged


api = dns.Cloudflare("toy-token", "a" * 32)
with patch.object(api, "request", side_effect=[
    {"result": [{"id": "first"}], "result_info": {"total_pages": 2}},
    {"result": [{"id": "second"}], "result_info": {"total_pages": 2}},
]) as request:
    assert [item["id"] for item in api.records(name="a.example.test")] == ["first", "second"]
    assert [call.kwargs["query"]["page"] for call in request.call_args_list] == [1, 2]
with patch.object(dns, "urlopen", side_effect=ValueError("invalid Authorization: toy-token")):
    try:
        api.request("GET")
    except RuntimeError as error:
        assert "toy-token" not in str(error)
    else:
        raise AssertionError("Transport failure was hidden")

configuration = {"recordType": "A", "records": ["a.example.test", "new.example.test"], "comment": "owner"}
a = API([{"id": "a", "type": "A", "name": "a.example.test", "content": "192.0.2.1"}])
dns.sync(a, configuration, "198.51.100.1")
assert [item[0] for item in a.calls] == ["update", "create"]
assert all(item["content"] == "198.51.100.1" for item in a.values)

configuration = {"recordType": "CNAME", "records": ["service.example.test"], "target": "example.test", "comment": "owner"}
c = API([
    {"id": "old-a", "type": "A", "name": "service.example.test", "content": "192.0.2.1"},
    {"id": "old-aaaa", "type": "AAAA", "name": "service.example.test", "content": "2001:db8::1"},
    {"id": "stale", "type": "CNAME", "name": "removed.example.test", "content": "example.test", "comment": "owner"},
    {"id": "manual", "type": "CNAME", "name": "manual.example.test", "content": "example.test", "comment": "other-owner"},
    {"id": "other-target", "type": "CNAME", "name": "elsewhere.example.test", "content": "other.example.test", "comment": "owner"},
])
dns.sync(c, configuration)
assert [call[0] for call in c.calls] == ["batch", "delete"]
assert c.calls[1] == ("delete", "stale")
assert {item["id"] for item in c.values} == {"batched", "manual", "other-target"}
assert c.calls[0][1]["deletes"] == [{"id": "old-a"}, {"id": "old-aaaa"}]

original = [{"id": "old", "type": "A", "name": "service.example.test", "content": "192.0.2.1"}]
failure = API(original, fail_batch=True)
try:
    dns.sync(failure, configuration)
except RuntimeError:
    pass
else:
    raise AssertionError("Failed replacement was ignored")
assert failure.values == original and [call[0] for call in failure.calls] == ["batch"]

protected = API([{"id": "txt", "type": "TXT", "name": "service.example.test", "content": "keep"}])
try:
    dns.sync(protected, configuration)
except ValueError:
    pass
else:
    raise AssertionError("Non-address record was replaced")
assert protected.calls == []
for invalid in ({**configuration, "target": "service.example.test"}, {**configuration, "records": ["service.example.test"] * 2}):
    try:
        dns.sync(API(), invalid)
    except ValueError:
        pass
    else:
        raise AssertionError("Invalid DNS configuration was accepted")
print("cloudflare synchronization: OK")
