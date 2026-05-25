# Announcements Feature Spec

## Clauses

- F.Announcements.1 Managers can create announcements for channels they belong to.
- F.Announcements.2 Staff cannot create announcements, including direct-route or forged-param attempts.
- F.Announcements.3 Announcement authors can edit title, body, audience, and acknowledgement requirement for 15 minutes after publish.
- F.Announcements.4 Edits and removals after the 15-minute grace window are rejected.
- F.Announcements.5 Managers can pin and unpin announcements in channels they belong to.
- F.Announcements.6 Removal is soft via `removed_at`; removed announcements leave receipts auditable and disappear from user-facing feeds.
- F.Announcements.7 Required acknowledgements exclude the author.
- F.Announcements.8 Acknowledgement and read writes are idempotent.
- F.Announcements.9 Managers can view receipt groups: acknowledged, read without acknowledgement, unread, and off shift.
- F.Announcements.10 Membership checks are enforced in context functions, not only in routes.

## Scaffold Gaps

- `create_announcement/2` and `update_announcement/3` are stubs.
- No soft-removal fields exist yet.
- Pin, unpin, remove, grace-window, and receipt grouping APIs are missing.
- Compose route is route-gated to on-shift users but not manager-gated in the LiveView or context.
