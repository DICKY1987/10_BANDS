# Plugin Interface

Custom tools can be added without modifying `QueueWorker.ps1` by dropping a PowerShell script
into this folder. Each plugin script is executed and must return a `PSCustomObject` with the
following members:

| Property        | Required | Description |
|-----------------|----------|-------------|
| `Name`          | Yes      | Human readable name shown in logs. |
| `Tool`          | Yes      | Tool identifier. Tasks using this value in `tool` will be routed to the plugin. |
| `Description`   | No       | Short summary for documentation purposes. |
| `ResolveCommand`| Yes      | Script block invoked with the task hashtable and optional prompt file path. Must return an object with `Executable` and `Arguments` properties. |

The plugin may inspect custom fields on the task payload. The object returned by
`ResolveCommand` can also include optional `Environment` (hashtable of environment
variables) in future revisions.

Plugins are reloaded when the worker starts. See `example_echo.ps1` for a minimal sample.
