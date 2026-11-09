########################################################################
#                                                                      #
#                         tests/test_infra.py                          #
#                                                                      #
########################################################################
"""
Author:            Kevin Street
Created on:        2026-11-09
Last modified on:  2026-11-09

Tests the Terraform without a cloud account: every file parses, every
provider is pinned to a range, the bucket can never be public, and the
CI role trusts only the listed repositories' main branch and can never
delete. CI's terraform validate checks the rest against the providers'
own schemas.
"""

########################################################################
#                                                                      #
#                               Imports                                #
#                                                                      #
########################################################################
# Standard library
from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Final

# Third-party
import hcl2
import pytest
from kds.args import required
from kds.logs import get_logger

# Local
from support import REPO

########################################################################
#                                                                      #
#                           Global constants                           #
#                                                                      #
########################################################################
log = get_logger(__name__)

########################################################################
#                                                                      #
#                           Local constants                            #
#                                                                      #
########################################################################
# log.debug("Sets the Terraform roots")
ROOTS: Final = ("aws", "databricks")


########################################################################
#                                                                      #
#                           Terraform tests                            #
#                                                                      #
########################################################################
# log.debug("Defines a parsed block without the parser's quotes and markers")
def _plain(value: Any = None) -> Any:
    """Returns the value without HCL's quotes or python-hcl2's markers.

    python-hcl2 keeps each string's own quotes and marks every block
    with __is_block__; this drops both.

    Args:
        value: A parsed value: a mapping, a list or a scalar.

    Returns:
        The same value, plain.
    """
    # log.debug("Cleans the value by its type")
    match value:
        case dict():
            # log.debug("Cleans each key and value, dropping the markers")
            return {_plain(k): _plain(v) for k, v in value.items() if not k.startswith("__")}
        case list():
            # log.debug("Cleans each item")
            return [_plain(v) for v in value]
        case str() if len(value) > 1 and value[0] == value[-1] == '"':
            # log.debug("Drops the quotes")
            return value[1:-1]
        case _:
            # log.debug("Returns anything else as it is")
            return value


# log.debug("Defines one root's parsed files")
def _root(name: str | None = None) -> dict[str, list[Any]]:
    """Returns every block of the root's files, merged by kind.

    Args:
        name: The root's folder under infra/. Required.

    Returns:
        Each kind of block (resource, data, terraform) and its blocks.
    """
    # log.debug("Takes the root, which the caller must give")
    name = required(name=name)
    # log.debug("Starts the merged blocks")
    blocks: dict[str, list[Any]] = {}
    # log.debug("Parses every file of the root")
    for path in sorted((REPO / "infra" / name).glob("*.tf")):
        # log.debug("Reads the file")
        with Path(path).open(encoding="utf-8") as handle:
            # log.debug("Adds its blocks")
            for kind, items in _plain(hcl2.load(handle)).items():
                # log.debug("Merges the kind's blocks")
                blocks.setdefault(kind, []).extend(items)
    # log.debug("Returns them")
    return blocks


# log.debug("Defines one named resource of a root")
def _resource(
    blocks: dict[str, list[Any]] | None = None, kind: str | None = None, name: str | None = None
) -> dict[str, Any]:
    """Returns the resource's body.

    Args:
        blocks: The root's blocks. Required.
        kind: The resource type, such as aws_iam_role. Required.
        name: Its name in the configuration. Required.

    Returns:
        The resource's arguments.
    """
    # log.debug("Takes the blocks, which the caller must give")
    blocks = required(blocks=blocks)
    # log.debug("Takes the type, which the caller must give")
    kind = required(kind=kind)
    # log.debug("Takes the name, which the caller must give")
    name = required(name=name)
    # log.debug("Finds it among the resources")
    return next(r[kind][name] for r in blocks["resource"] if kind in r and name in r[kind])


# log.debug("Defines the test that every provider is pinned")
@pytest.mark.parametrize("root", ROOTS)
def test_every_root_pins_terraform_and_its_providers(root: str) -> None:
    """A provider without a range would change under a later init.

    Args:
        root: The root's folder.
    """
    # log.debug("Reads the root's terraform block")
    (settings,) = _root(root)["terraform"]
    # log.debug("Lists each provider's version range")
    ranges = [p["version"] for block in settings["required_providers"] for p in block.values()]
    # log.debug("Checks Terraform and each provider have a range")
    assert (bool(settings["required_version"]), all(ranges), bool(ranges)) == (True, True, True)


# log.debug("Defines the test that the bucket stays private")
def test_the_bucket_blocks_every_kind_of_public_access() -> None:
    """All four public-access switches are on."""
    # log.debug("Reads the bucket's public-access block")
    block = _resource(_root("aws"), "aws_s3_bucket_public_access_block", "lake")
    # log.debug("Checks each switch")
    assert all(
        block[k] is True
        for k in (
            "block_public_acls",
            "block_public_policy",
            "ignore_public_acls",
            "restrict_public_buckets",
        )
    )


# log.debug("Defines the test of the role's trust and rights")
def test_the_ci_role_trusts_listed_repositories_and_cannot_delete() -> None:
    """Only the deployers' main may assume it; it cannot delete."""
    # log.debug("Reads the root")
    blocks = _root("aws")
    # log.debug("Serializes the policy documents to search them")
    documents = json.dumps(blocks["data"])
    # log.debug("Serializes the locals, where the trusted subjects are built")
    built = json.dumps(blocks["locals"])
    # log.debug("Checks the trust is the subjects built for each deployer, by name and id")
    assert (
        "${local.github_subjects}" in documents,
        "repo:%s@%d/%s@%d:ref:%s" in built,
        "var.deployers" in built,
    ) == (True, True, True)
    # log.debug("Checks no statement grants a delete or every action")
    assert ("s3:Delete" not in documents, '"s3:*"' in documents) == (True, True)
    # log.debug("Checks the one s3:* is the TLS deny")
    assert documents.count('"Deny"') == 1


# log.debug("Defines the test that every deployer is named by name and id")
def test_every_deployer_names_its_repository_and_id() -> None:
    """GitHub's immutable subject carries both a name and an id."""
    # log.debug("Reads the deployers variable")
    (deployers,) = [v["deployers"] for v in _root("aws")["variable"] if "deployers" in v]
    # log.debug("Lists the default deployers")
    listed = deployers["default"]
    # log.debug("Checks each has an owner/name and a numeric id")
    assert listed and all(
        d["repository"].count("/") == 1 and isinstance(d["id"], int) for d in listed
    )
    # log.debug("Checks each repository is listed once")
    assert len({d["id"] for d in listed}) == len(listed)
