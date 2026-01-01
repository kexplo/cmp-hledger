local source = {}
local cmp = require('cmp')

source.new = function()
  local self = setmetatable({}, { __index = source })
  self.items = nil
  return self
end

source.get_trigger_characters = function()
  return {
    'Ex',
    'In',
    'As',
    'Li',
    'Eq',
    'E:',
    'I:',
    'A:',
    'L:',
  }
end

local ltrim = function(s)
  return s:match('^%s*(.*)')
end

local split = function(str, sep)
  local t = {}
  for s in string.gmatch(str, '([^' .. sep .. ']+)') do
    table.insert(t, s)
  end
  return t
end

local function run_hledger_accounts(account_path)
  -- if the system is not Windows, run the command directly
  if vim.loop.os_uname().sysname ~= "Windows_NT" then
    local cmd = string.format(
      "%s accounts -f %s 2>&1",
      vim.fn.shellescape(vim.b.hledger_bin),
      vim.fn.shellescape(account_path)
    )
    local p = assert(io.popen(cmd))
    local out = p:read("*all")
    p:close()
    return out
  end

  -- on Windows, create and run a temporary .bat file
  local bat = vim.fn.tempname() .. ".bat"
  local hbin  = vim.fn.shellescape(vim.b.hledger_bin)
  local jfile = vim.fn.shellescape(account_path)

  -- bat 내에서도 quoting은 유지 (vim-plug 스타일)
  local lines = {
    "@echo off",
    "setlocal ENABLEDELAYEDEXPANSION",
    "chcp 65001>nul",
    string.format("%s accounts -f %s 2>&1", hbin, jfile),
    "endlocal",
  }

  vim.fn.writefile(lines, bat)

  -- run the .bat file
  local cmd = string.format('cmd /C "%s"', bat)
  local output = vim.fn.system(cmd)

  -- delete the temporary .bat file
  pcall(vim.fn.delete, bat)

  return output
end

local get_items = function(account_path)
  local output = run_hledger_accounts(account_path)
  local t = split(output, "\n")

  local items = {}
  for _, s in pairs(t) do
    table.insert(items, {
      label = s,
      kind = cmp.lsp.CompletionItemKind.Property,
    })
  end

  return items
end

source.complete = function(self, request, callback)
  if vim.bo.filetype ~= 'ledger' then
    callback()
    return
  end
  if vim.fn.executable("hledger") == 1 then
    vim.b.hledger_bin = "hledger"
  elseif vim.fn.executable("ledger") == 1 then
    vim.b.hledger_bin = "ledger"
  else
    vim.api.nvim_echo({
      { 'cmp_hledger',                         'ErrorMsg' },
      { ' ' .. 'Can\'t find hledger or ledger' },
    }, true, {})
    callback()
    return
  end
  local account_path = vim.api.nvim_buf_get_name(0)
  if not self.items then
    self.items = get_items(account_path)
  end

  local prefix_mode = false
  local input = ltrim(request.context.cursor_before_line):lower()
  local prefixes = split(input, ":")
  local pattern = ''

  for i, prefix in ipairs(prefixes) do
    if i == 1 then
      pattern = string.format('%s[%%w%%-]*', prefix:lower())
    else
      pattern = string.format('%s:%s[%%w%%-]*', pattern, prefix:lower())
    end
  end
  if #prefixes > 1 and pattern ~= '' then
    prefix_mode = true
  end

  local items = {}
  for _, item in ipairs(self.items) do
    if prefix_mode then
      if string.match(item.label:lower(), pattern) then
        table.insert(items, {
          word = item.label,
          label = item.label,
          kind = item.kind,
          textEdit = {
            filterText = input,
            newText = item.label,
            range = {
              start = {
                line = request.context.cursor.row - 1,
                character = request.offset - string.len(input),
              },
              ['end'] = {
                line = request.context.cursor.row - 1,
                character = request.context.cursor.col - 1,
              },
            },
          },
        })
      end
    else
      if vim.startswith(item.label:lower(), input) then
        table.insert(items, item)
      end
    end
  end
  callback(items)
end

return source
