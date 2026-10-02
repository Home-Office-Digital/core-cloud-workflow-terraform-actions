#!/usr/bin/env python3
"""Summarise a Terraform plan as markdown for the GitHub Actions job summary.

Usage: summarise_plan.py <tfplan.json>
"""

import json
import sys

# mapping of TF plan actions to Markdown snippets
ACTIONS = {
    ("create",): "Create",
    ("update",): "Update in place",
    ("delete",): "**Destroy**",
    ("delete", "create"): "**Destroy** and recreate",
    ("create", "delete"): "**Destroy** and recreate",  # create_before_destroy
    ("no-op",): None,
    ("read",): None,
}

plan = json.load(open(sys.argv[1], encoding="utf-8"))

rows = []
plan_plans_destruction = False

# loop through JSON and generate table rows
for rc in plan.get("resource_changes", []):
    actions = rc.get("change", {}).get("actions", [])
    if "delete" in actions:
        plan_plans_destruction = True
    action = ACTIONS.get(tuple(actions), "Other")
    if action:
        rows.append((action, rc.get("address", "?"), rc.get("type", "?")))

out = ["## Plan summary\n"]

if plan_plans_destruction:
    out.append("> [!WARNING]")
    out.append("> This plan will destroy resources when applied.\n")

if rows:
    out.append("| Action | Resource | Type |")
    out.append("| --- | --- | --- |")
    out += [f"| {action} | `{resource}` | `{rtype}` |" for action, resource, rtype in rows]
else:
    out.append("__No resource changes. Your infrastructure matches the configuration.__")
print("\n".join(out))
