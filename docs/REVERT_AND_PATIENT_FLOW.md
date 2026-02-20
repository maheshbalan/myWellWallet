# Why the revert didn’t overwrite patient/query code (and how to avoid confusion)

## What was reverted (GUI restore)

Only these three files were reverted to the last commit (HEAD) when you asked to restore the previous GUI:

- `lib/main.dart` (theme, app setup)
- `lib/screens/login_screen.dart` (login UI)
- `lib/screens/registration_screen.dart` (registration UI)

Command used:  
`git checkout HEAD -- lib/main.dart lib/screens/login_screen.dart lib/screens/registration_screen.dart`

## What was not reverted

These were **not** touched by that revert:

- `lib/screens/home_screen.dart` – patient context, Gemma context, query UI
- `lib/providers/query_provider.dart` – “Patient ID not available”, processQuery
- `lib/providers/patient_provider.dart` – foundPatient, search
- `lib/providers/auth_provider.dart` – biometric/PIN fixes

So **patient/query behavior was not overwritten by the GUI revert**. The revert only replaced the three UI/theme files with their committed versions.

## Why it looked like “GUI change clobbered functionality”

1. **Same bug in committed code**  
   The “Patient ID not available” behavior comes from logic that was already in the last commit (752fdb9) in `home_screen.dart` and `query_provider.dart`. The bug: when you go to Profile then back to Home, `_establishPatientContext()` runs again and calls `searchPatientByNameAndDOB`, which **clears** `foundPatient` at the start of the search, so for a while (or if the search fails) there is no patient ID for queries.

2. **No patient logic in the reverted files**  
   The reverted files do not contain patient context or query logic. `main.dart` only wires providers (PatientProvider, QueryProvider, `setPatientProvider`); that wiring is the same in HEAD and was not changed in a way that would remove patient support.

3. **Possible confusion with “working before”**  
   If it felt like it worked before the GUI changes, possible explanations (without other evidence) are:  
   - A different usage pattern (e.g. not going Profile → Home before querying).  
   - Uncommitted changes in another file (e.g. `home_screen.dart` or `query_provider.dart`) that were later lost or overwritten by some other edit (not by this revert, since those files were not reverted).

## Fix that was added (after the revert)

In `lib/screens/home_screen.dart`, `_establishPatientContext()` was updated to:

- Check if `PatientProvider.foundPatient` already matches the current user (name + DOB).
- If it matches, **reuse** that patient and only update Gemma context (no new search).
- So when you come back from Profile to Home, we no longer clear `foundPatient`, and “Patient ID not available” should stop for that flow.

This fix is in the same file that has always held the patient-context logic; it was not “restored” from a reverted file.

## How to avoid “GUI changes clobbering functionality”

1. **Revert only what you mean to**  
   Use `git checkout HEAD -- <file>` (or `git restore --source=HEAD -- <file>`) only for the specific files you intend to roll back (e.g. theme/login/registration). Do not revert whole directories or “all changed files” unless you’re sure no logic lives there.

2. **See what you’re reverting**  
   Before reverting, run:  
   `git diff HEAD -- lib/main.dart lib/screens/login_screen.dart lib/screens/registration_screen.dart`  
   so you know exactly what will go back to the last commit.

3. **Commit working behavior first**  
   Before large GUI or refactor work, commit a known-good state (e.g. “patient flow works”) so you can diff or revert with confidence and know that logic lives in which commit.

4. **Keep UI and logic separate where possible**  
   Prefer theme/layout in one place (e.g. `main.dart`, widgets) and business logic in another (e.g. providers, `home_screen` methods). That way reverting “GUI” files is less likely to touch behavior.

5. **Document critical flows**  
   A short note (e.g. in `docs/`) listing “patient context + query works when: …” helps confirm after any revert that the right code paths are still in place.
