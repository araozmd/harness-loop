# What a harness is

The exact text that agents and tests read is in [agents/HARNESS.md](agents/HARNESS.md).

A harness is everything built around a model so it can work on a repository in a
repeatable way: the context it reads, the tools it may call, the memory it keeps between
sessions and the verification that proves its work. The model is the engine; the harness is
the chassis.

The method — the loop, specs, gates, code over prose and review — is explained in
[CONCEPTS.md](CONCEPTS.md). How a task moves through the roles is in
[WORKFLOW.md](WORKFLOW.md). The [rationale and deletion ledger](RATIONALE.md) records why
the harness's mechanisms exist and what evidence would justify removing one.
