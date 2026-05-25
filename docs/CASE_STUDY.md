

I started with claude design, started discussing the initial idea of having a system that would help luxury hotels to replace whatsapp and engage people at the same time.

This session lasted about 1h, we had lot of back of forth until my claude design credits ended. 

From that, I wrote the FOYER.md file, in which I describe the product features. That also took around 1h, if combined with repurposing some of the claude.md files that I had, and organizing it together with test conventions and workflow. 

# Appendix A — Session transcripts

## Session 1 - project bootstrap

### Prompt 1
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


### Prompt 2
also make sure you link the newly created AGENTS.MD to our claude.md (agents.md came with phoenix and liveview, so are development guidelines)


## Session 2 - mobile Ui mocks

### Prompt 1
Read the designs and the project files and let's scaffold the Mobile UI. Have a basic version of the UI working, define the contexts, the routes, the models, the DB tables, etc., and continue from there. The data should be mocked at this point, but it will force us to define liveviews, contexts and the data model.

The feature groups I envision are (with matching liveviews and contexts)
- Chats
- Announcements
- Recognitions
- Channels
- Today
- Profile
- People Directory
- Shifts

This is a big lift, but an important one. It will make it easier later to work in parallel.

I would like you to first scaffold a mocked UI and a smoke test that ensures we can reach every part and that the UI works and is as designed. 

We should have a mobile version we should have Today, House, Chat, and Me (which shows the profile). At this point, Mocked data. We want to have a functioning UI, but backed by mocked data. 

Don't go too deep into the details at this point, we will evolve this later when we work on the feature groups later.

This don't need specs, we should have a single plan created by a opus agent and a codex agent review. Later another opus agent shall implement it and another codex agent should review it.

