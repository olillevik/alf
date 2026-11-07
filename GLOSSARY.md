# Upstream skills

The plugin's catalogue of upstream skills. It keeps each upstream skill pinned and exposes it through a wrapper skill that can add local instructions.

## Copies and pins

**Upstream**:
A GitHub repository that upstream skills are copied from. Each upstream has its own folder in the catalogue, with its license and its pin record.
_Avoid_: Source, origin

**Upstream skill**:
A byte-for-byte copy of one skill folder from an upstream. An update replaces it in full.
_Avoid_: Asset, vendored skill, copy

**Catalogue**:
The set of all upstream skills, grouped by upstream.
_Avoid_: Library, registry

**Pin**:
The revision a dependency is fixed at. An upstream skill is pinned in the catalogue, and a team pins an ALF release in its `apm.yml`. A pinned upstream skill is skipped by the weekly update until it is moved to latest.
_Avoid_: Lock, freeze

**Latest**:
The newest revision on an upstream's default branch that changes an upstream skill's folder.

## Skills

**Wrapper**:
A plugin skill that points at one upstream skill and adds the overlay. The upstream skill is the skill being wrapped.
_Avoid_: Alias, proxy

**In-house skill**:
A plugin skill written in this repo, with no upstream skill behind it.
_Avoid_: Full skill, standalone skill

**Overlay**:
Local instructions a wrapper adds after following its upstream skill.
_Avoid_: Patch, customisation

**Dependency**:
A skill that another skill calls by name or links to.
_Avoid_: Requirement, related skill

**Flow**:
A path through the skills from one starting situation to a result. The main flow runs from idea to ship.
