# Interoperability review

`agent-stream.nvim` decorates existing buffers, so its defaults should follow the active Neovim theme and preserve editor preferences. Explicit options cover presentation differences without reading other plugins' private configuration.

The review inspected these source revisions. Links pin the evidence to the reviewed code rather than a moving branch.

| Reference | Observed pattern | Decision |
| --- | --- | --- |
| [Gitsigns highlights](https://github.com/lewis6991/gitsigns.nvim/blob/851a051e2bd2caba97e23314c68d69f1b1cf5d19/lua/gitsigns/highlight.lua) | Default highlight links, fallback groups, and colorscheme refresh | Adopt native semantic links and respect existing definitions. Omit cross-plugin fallback chains. |
| [mini.diff](https://github.com/nvim-mini/mini.nvim/blob/6f0cd5049f414932ba55a5d6f3282a59d55c71a3/lua/mini/diff.lua) | Default highlights restored on `ColorScheme`; configurable decoration priority | Adopt lifecycle handling and an explicit sign priority. Keep the existing whole-file review model. |
| [Oil configuration](https://github.com/stevearc/oil.nvim/blob/b73018b75affd13fa38e2fc94ef753b465f770d7/lua/oil/config.lua) | Default mappings can be disabled; explicit mappings replace complete entries | Make mappings opt-in and preserve complete override definitions. No additional mapping framework. |
| [Trouble configuration](https://github.com/folke/trouble.nvim/blob/bd67efe408d4816e25e8491cc5ad4088e708a69a/lua/trouble/config/init.lua) | Presentation symbols are configurable | Expose three shared symbols with ordinary-text defaults. Omit presets and automatic font detection. |
| [Neo-tree defaults](https://github.com/nvim-neo-tree/neo-tree.nvim/blob/ffdf8d93c8db197a5cab072a18cc8da69d490b81/lua/neo-tree/defaults.lua) | Renderer components receive configuration and optional icon support is guarded | Retain explicit component registration; background updates must not load the explorer. No new adapters. |

## Boundaries

Native highlight links follow theme changes without copying color values. Explicit `highlights` entries remain available for fixed colors or intentional links to another plugin. A supplied definition replaces the entire default, so a default `link` cannot suppress a custom `fg` value.

Neovim settings are not all equivalent to review preferences. `autoread` does not authorize automatic acceptance, and whitespace-ignore diff settings must not hide external changes awaiting review. The plugin preserves those options and its existing comparison semantics.

Mappings are disabled by default. Explicit mappings retain the existing action names, and command-based preview hints remain accurate when users choose their own keys. Repeated setup replaces plugin-owned registrations without deleting mappings subsequently replaced by the user.

The reviewed plugins are references, not dependencies. Tests cover native themes, explicit overrides, disabled integrations, and neighboring decorations; compatibility with every theme or custom sign-column implementation is not implied.
