#!/usr/bin/env python3
"""Rewrites a temporary copy of lib/api-spec/openapi.yaml into a shape that
swift-openapi-generator 1.14 accepts. The real spec is never touched.

Workaround 1 - nullable references.
  The spec marks a nullable object as the OpenAPI 3.1 idiom
      oneOf: [ { $ref: X }, { type: "null" } ]
  The generator does not support a `null` subschema: it warns and drops the
  WHOLE property (e.g. CalibrationStatus.checks, WorkoutLogInput.calibrationFeedback).
  Rewrite: the property becomes plain `$ref: X` and is removed from its parent's
  `required` list, so Swift gets `X?` (decodes both null and a missing key).
  Side effect: an encoded nil is omitted instead of sent as `null`.

Usage: openapi-preprocess.py <in.yaml> <out.yaml>   (needs PyYAML)
"""
import sys

import yaml


def null_branch(schema):
    return isinstance(schema, dict) and schema.get("type") == "null" and len(schema) == 1


def strip_null_union(prop):
    """Returns the property without its null branch, or None if it is not a null union."""
    if not isinstance(prop, dict):
        return None
    for key in ("oneOf", "anyOf"):
        branches = prop.get(key)
        if not isinstance(branches, list) or not any(null_branch(b) for b in branches):
            continue
        rest = [b for b in branches if not null_branch(b)]
        out = {k: v for k, v in prop.items() if k != key}
        if len(rest) == 1:
            out.update(rest[0])
        else:
            out[key] = rest
        return out
    return None


rewritten = []


def walk(node, path):
    if isinstance(node, dict):
        props = node.get("properties")
        if isinstance(props, dict):
            for name, prop in list(props.items()):
                fixed = strip_null_union(prop)
                if fixed is not None:
                    props[name] = fixed
                    if isinstance(node.get("required"), list) and name in node["required"]:
                        node["required"].remove(name)
                    rewritten.append(f"{path}/properties/{name}")
        for k, v in node.items():
            walk(v, f"{path}/{k}")
    elif isinstance(node, list):
        for i, v in enumerate(node):
            walk(v, f"{path}/{i}")


def main():
    src, dst = sys.argv[1], sys.argv[2]
    with open(src, encoding="utf-8") as f:
        spec = yaml.safe_load(f)
    walk(spec, "#")
    with open(dst, "w", encoding="utf-8") as f:
        yaml.safe_dump(spec, f, sort_keys=False, allow_unicode=True)
    for p in rewritten:
        print(f"preprocess: nullable $ref -> optional: {p}", file=sys.stderr)


main()
