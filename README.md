# CALL Matcher - Neovim Plugin

A Neovim plugin that provides enhanced C code navigation and visualization by detecting and highlighting various call patterns in real-time.

## Demo

![Demo](examples/demo.gif)

## Features

- **Real-time Call Visualization**: Automatically detects and displays method calls inline
- **Multiple Pattern Support**:
  - `CALL(class, name, method, params)` - Object method calls
  - `NSCALL(namespace, name, params)` - Namespace function calls
  - `MTD(class, method, params)` - Method definitions
  - `NSMTD(namespace, method, params)` - Namespace method definitions
- **Automatic Triggering**: Works on buffer enter, write, and text changes
- **Clean Formatting**: Normalizes whitespace and parameters for better readability
- **C Focused**: Specifically designed for C codebases

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
return {
  "rijuyuezhu/call-matcher",
  ft = { "c", "h" },  -- Filetypes to load for
  config = function()
    require("call-matcher").setup()
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "rijuyuezhu/call-matcher",
  ft = { "c", "h" },
  config = function()
    require("call-matcher").setup()
  end
}
```

## Usage

The plugin works automatically once installed and configured. It will:

1. Scan C files for special call patterns
2. Display virtual text annotations showing:
   - Method signatures
   - Parameter lists
   - Class/namespace context
3. Update in real-time as you edit

### Supported Patterns

1. **Object Method Calls** (`CALL`):
   ```c
   CALL(MyClass, instance, methodName, param1, param2)
   ```
   Displays as: `(MyClass&)instance.methodName(param1, param2)`

2. **Namespace Function Calls** (`NSCALL`):
   ```c
   NSCALL(MyNamespace, functionName, param1, param2)
   ```
   Displays as: `MyNamespace::functionName(param1, param2)`

3. **Method Definitions** (`MTD`):
   ```c
   MTD(MyClass, methodName, param1, param2)
   ```
   Displays as: `MyClass.methodName(param1, param2)`

4. **Namespace Method Definitions** (`NSMTD`):
   ```c
   NSMTD(MyNamespace, methodName, param1, param2)
   ```
   Displays as: `MyNamespace::methodName(param1, param2)`

## Configuration

Currently the plugin works with default settings. Future versions may include configuration options for:

- Virtual text styling
- Trigger events
- Pattern customization

## Troubleshooting

If virtual text isn't appearing:

1. Verify the filetype is `c` or `h`
2. Check for proper pattern syntax
3. Ensure the plugin is properly installed and configured

## License

MIT
