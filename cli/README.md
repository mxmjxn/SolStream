# solstream CLI

The `solstream` command-line interface. Thin wrapper over the SolStream Ansible playbook + diagnostic helpers.

```bash
solstream install          # run the install playbook
solstream status           # show service state + URLs
solstream urls             # print URLs only (machine-readable)
solstream doctor           # health checks
solstream metrics 60       # capture 60s of GPU/encoder metrics
solstream version          # print version
```

See the [project root README](https://github.com/mxmjxn/SolStream) for the full story.
