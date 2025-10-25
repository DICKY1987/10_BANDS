# CI/CD Integration Tips

## Webhooks
Run `scripts/TaskWebhook.ps1` on a build agent and POST JSON payloads:

```bash
curl -X POST http://localhost:8123/enqueue -H 'Content-Type: application/json' \
  -d '{"tool": "git", "args": ["fetch", "--all"], "priority": "high"}'
```

## Jenkins
- Add a post-build step executing `pwsh -File scripts/TaskWebhook.ps1 -Prefix http://0.0.0.0:8123/`.
- Use a `curl` stage to enqueue follow-up smoke tests or git fetches.

## GitHub Actions
Use the `powershell` shell to post a task:

```yaml
- name: Enqueue verification
  shell: pwsh
  run: |
    $body = @{ tool = 'git'; args = @('status','-sb'); priority = 'normal' } | ConvertTo-Json -Compress
    Invoke-RestMethod -Method Post -Uri 'http://localhost:8123/enqueue' -Body $body -ContentType 'application/json'
```

## File Watcher Mode
`scripts/TaskFileWatcher.ps1` can run alongside CI agents to queue tasks whenever code changes are detected (useful for local developer workflows or pre-commit checks).
