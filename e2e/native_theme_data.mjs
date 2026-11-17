import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';

// Native screenshot tests consume the same palette definitions as the app.
// Pure-JS port of native_theme_data.py (same regexes, same output shape), so
// the theme scripts no longer have to spawn a Python helper.
function color(value) {
  value = value.toLowerCase();
  return '#' + (value.endsWith('ff') ? value.slice(0, 6) : value);
}

function load() {
  const source = readFileSync(fileURLToPath(new URL('../src/config/theme_presets.zig', import.meta.url)), 'utf8');
  const tokenSource = source.split('pub fn tokens').slice(1).join('pub fn tokens').split('pub fn ansi')[0];
  const defaultsSource = source.split('pub fn terminalDefaults').slice(1).join('pub fn terminalDefaults');
  const pattern = /if \(std\.mem\.eql\(u8, id, "([^"]+)"\)\) return \.\{(.*?)\};/gs;
  const fields = /\.(\w+) = 0x([\da-fA-F]{8})/g;
  const collect = (text, key) => {
    const out = {};
    for (const [, theme, body] of text.matchAll(pattern)) {
      const roles = {};
      for (const [, role, value] of body.matchAll(fields)) roles[key(role)] = color(value);
      out[theme] = roles;
    }
    return out;
  };
  const themes = collect(tokenSource, (role) => '--' + role.replaceAll('_', '-'));
  const terminals = collect(defaultsSource, (role) => role);
  const a = Object.keys(themes).sort(), b = Object.keys(terminals).sort();
  if (!a.length || a.join('\n') !== b.join('\n')) throw new Error('Native theme and terminal defaults are incomplete');
  return {themes, terminalPalettes: terminals};
}

export const nativeThemeData = load();
