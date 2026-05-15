const path = require('path');
const { execSync } = require("child_process");
const glob  = require('glob').sync

if (!process.env.THEME) {
  throw "tailwind.config.js: missing process.env.THEME"
  process.exit(1)
}

const themeConfigFile = execSync(`bundle exec bin/theme tailwind-config ${process.env.THEME}`).toString().trim()
let themeConfig = require(themeConfigFile)

const defaultTheme = require('tailwindcss/defaultTheme')
const colors = require('tailwindcss/colors')

// Lewsnetter design system overrides. See DESIGN.md.
//
// 1. base palette → zinc (was slate). The theme already wires primary/secondary
//    to `--primary-*` CSS variables that switch based on `theme.rb`'s color
//    (we set it to :orange, which makes --primary-* resolve to Tailwind's
//    orange palette — i.e. the #EA580C accent).
const themeColors = themeConfig.theme.extend.colors
themeConfig.theme.extend.colors = ({ colors }) => ({
  ...themeColors({ colors }),
  base: colors.zinc
})

// 2. Typography — Geist Sans for everything, Geist Mono for metadata.
themeConfig.theme.extend.fontFamily = themeConfig.theme.extend.fontFamily || {}
themeConfig.theme.extend.fontFamily.sans = ['Geist', ...defaultTheme.fontFamily.sans]
themeConfig.theme.extend.fontFamily.mono = ['"Geist Mono"', ...defaultTheme.fontFamily.mono]

// 3. Border radius — sharp corners, 12px ceiling. Anti-bubble.
themeConfig.theme.extend.borderRadius = {
  DEFAULT: '6px',
  sm: '4px',
  md: '6px',
  lg: '8px',
  xl: '12px'
}

module.exports = themeConfig
