## Snapshot tests

* If this project uses snapshot tests: a change that makes snapshots need
  re-recording is a strong signal about what the change did, and the
  snapshots are most useful when the person reviewing can compare *before*
  directly with *after*. So in an interactive session with a person, **never
  commit re-recorded snapshot images until they have reviewed and accepted
  them**; do not commit the half-finished states in between. Working
  independently, commit as you like: the final pull request shows the
  before and after anyway.
