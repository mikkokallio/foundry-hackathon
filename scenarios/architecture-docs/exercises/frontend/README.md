# B9 local client build materials

This is a participant build, not a prebuilt application or new cloud deployment.
Start from [the bonus journey](../../../../docs/bonus/b9-local-app.md).

1. Use the **rendered** `prompts\frontend-prompt.md` in your exported participant
   pack. Its [source PROMPT](../prompts/frontend-prompt.md) contains placeholders;
   do not send those unresolved placeholders to your runtime.
2. Give your coding assistant the [SPEC](SPEC.md), actual exported OpenAPI and
   a selected immutable agent binding. Read generated code before running it.
3. Keep the app in your own ignored output directory, bind locally and use your
   own server-side Entra identity. Never copy a token into frontend configuration.
4. Build and validate the small real-data path before choosing an
   [EXTEND](EXTEND.md) task. Missing prerequisites are blockers, not sample data.

Follow the generated project's actual dependency/start commands; no application
framework or fictitious universal start command is assumed here.
All agent/output-parser/rendering changes need the repository's genuine
smoke/regression and native provenance evidence before acceptance.
