# Appendix A — Session transcripts

## First session - project bootstrap

```
Start this project, create a Nix file, and start with a README. Make sure we have all dependencies and that we can start our LiveView application.

The claude.md file has all our guidelines and what the project is and links to it. Make sure you use nix to handle
the dependencies and that you create a .tool_versions for non nix users. We should have a utility function that
allows us to start/stop the db if not yet started.

Make sure we have a fake version of all the required env variables in `.envrc`. Move `DATABASE_URL` to the
`.envrc.local` file and create an `.envrc.local.sample` in which we explain to the users what is needed in there.
You should also set a dummy `DATABASE_URL` in the `.envrc`.

Trigger a sonnet agent to continue autonomously until the app starts without warnings, and that all tests pass.
There is no need to create specs/plans here, but we should trigger a verify step afterwards to ensure everything is
set up per our guidelines.

While the Sonnet agent develops the code, ensure we have a proper README, explaining the overall idea of the project
and linking to documentation we already have in place. Also, make sure we have a guide on how to start the
application.
```

```
also make sure you link the newly created AGENTS.MD to our claude.md (agents.md came with phoenix and liveview, so are development guidelines)
```


