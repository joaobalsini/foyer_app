# Recognitions Feature Spec

## Clauses

- F.Recognitions.1 Any on-shift user can send recognition to another user.
- F.Recognitions.2 Self-recognition is rejected.
- F.Recognitions.3 Recognition values are exactly `care`, `craft`, `warmth`, `discretion`, `initiative`, and `excellence`.
- F.Recognitions.4 At least one recognition value is required.
- F.Recognitions.5 Only managers can grant bonus points.
- F.Recognitions.6 Bonus point tiers are exactly `0`, `10`, `25`, `50`, and `100`.
- F.Recognitions.7 Point balance updates and point ledger entries are committed in one `Ecto.Multi`.
- F.Recognitions.8 Removing a recognition is soft and reverses granted points with an auditable ledger delta.
- F.Recognitions.9 Authors can edit or remove a recognition for 15 minutes after creation.
- F.Recognitions.10 Public recognitions appear in public feeds and profile cards; private recognitions are visible only to sender and recipient.

## Scaffold Gaps

- `give/2` and `update_recognition/3` are stubs.
- `team` is currently included as a recognition value and must be removed.
- Soft-removal fields and the points ledger table do not exist yet.
- Profile and feed reads do not yet filter removed recognitions.
