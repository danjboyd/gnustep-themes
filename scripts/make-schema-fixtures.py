#!/usr/bin/env python3
"""Regenerates Tests/Fixtures/Schema/*.plist: one fully featured good file
and single-defect variants. Each bad file differs from good.plist in one
place; the expected finding is listed in Tests/GTSSchemaValidatorTests.m.
Run: python3 -I scripts/make-schema-fixtures.py"""
import copy, os, sys

def q(s):
    s = str(s)
    if s and all(c.isalnum() or c in '._-' for c in s):
        return s
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'

def ser(v, ind=0):
    p = '  ' * ind
    if isinstance(v, dict):
        return '{\n' + ''.join('%s  %s = %s;\n' % (p, q(k), ser(x, ind + 1)) for k, x in v.items()) + p + '}'
    if isinstance(v, list):
        return '(' + ', '.join(ser(x, ind + 1) for x in v) + ')'
    return q(v)

GOOD = {
  'SchemaVersion': '1', 'Theme': 'Fixture', 'ThemeIdentifier': 'org.example.themes.fixture',
  'Groups': [{'Identifier': 'appearance', 'Title': 'Appearance'}, {'Identifier': 'behavior', 'Title': 'Behavior'}],
  'Settings': [
    {'Identifier': 'fx.scheme', 'Key': 'FxScheme', 'Type': 'enum', 'CaseInsensitive': 'YES',
     'Values': [{'Value': 'light', 'Title': 'Light'}, {'Value': 'dark', 'Title': 'Dark'},
                {'Value': 'default', 'Title': 'Theme default', 'Help': 'An explicit stored value, not absence.'}],
     'Scopes': ['global', 'application'], 'Group': 'appearance', 'Title': 'Style',
     'Unset': {'Behavior': 'dynamic', 'Help': 'Follows the desktop colour scheme.'},
     'Apply': 'live'},
    {'Identifier': 'fx.prefer-dark', 'Key': 'FxPreferDark', 'Type': 'bool',
     'Scopes': ['global', 'application'], 'Group': 'appearance', 'Title': 'Prefer dark',
     'Unset': {'Behavior': 'static', 'Value': 'NO'}, 'Overlaps': ['fx.scheme'], 'Apply': 'newWindows'},
    {'Identifier': 'fx.menu', 'Key': 'FxMenuStyle', 'Type': 'enum',
     'Values': ['primary', 'menubar'], 'Scopes': ['application'], 'Group': 'behavior', 'Title': 'Menu style',
     'Unset': {'Behavior': 'static', 'Value': 'primary'},
     'Precedence': ['argument', 'application', {'Source': 'applicationInfo', 'Values': ['menubar']}, 'global',
                    'applicationInfo'],
     'InfoKey': 'FxMenuStyleInfo', 'Apply': 'restart'},
    {'Identifier': 'fx.scale', 'Key': 'FxScale', 'Type': 'number', 'Minimum': '0.8', 'Maximum': '2.0',
     'Scopes': ['global'], 'Group': 'appearance', 'Title': 'Text size',
     'Unset': {'Behavior': 'static', 'Value': '1.0'}, 'Apply': 'restart'},
    {'Identifier': 'fx.accent', 'Key': 'FxAccentName', 'Type': 'string', 'Scopes': ['global'],
     'Group': 'appearance', 'Title': 'Accent name', 'Status': 'unstable',
     'Unset': {'Behavior': 'static', 'Value': 'blue'},
     'DependsOn': {'Setting': 'fx.scheme', 'Values': ['DARK']}, 'Apply': 'restart'},
  ]}

def setting(doc, ident):
    return next(s for s in doc['Settings'] if s['Identifier'] == ident)

def variant(fn):
    d = copy.deepcopy(GOOD); fn(d); return d

V = {
  'good': lambda d: None,
  'bad-version-2': lambda d: d.update(SchemaVersion='2'),
  'bad-version-fraction': lambda d: d.update(SchemaVersion='1.5'),
  'bad-missing-theme-identifier': lambda d: d.pop('ThemeIdentifier'),
  'bad-unknown-type': lambda d: setting(d, 'fx.scale').update(Type='float'),
  'bad-missing-unset': lambda d: setting(d, 'fx.scale').pop('Unset'),
  'bad-dynamic-with-value': lambda d: setting(d, 'fx.scheme')['Unset'].update(Value='default'),
  'bad-unset-value-invalid': lambda d: setting(d, 'fx.menu')['Unset'].update(Value='ribbon'),
  'bad-unset-value-out-of-range': lambda d: setting(d, 'fx.scale')['Unset'].update(Value='3'),
  'bad-apply': lambda d: setting(d, 'fx.scale').update(Apply='immediately'),
  'bad-scope': lambda d: setting(d, 'fx.scale').update(Scopes=['user']),
  'bad-duplicate-identifier': lambda d: setting(d, 'fx.accent').update(Identifier='fx.scale'),
  'bad-status-typo': lambda d: setting(d, 'fx.accent').update(Status='Unstable'),
  'bad-depends-dangling': lambda d: setting(d, 'fx.accent')['DependsOn'].update(Setting='fx.colour'),
  'bad-depends-value': lambda d: setting(d, 'fx.accent')['DependsOn'].update(Values=['purple']),
  'bad-overlaps-dangling': lambda d: setting(d, 'fx.prefer-dark').update(Overlaps=['fx.colour-scheme']),
  'bad-group-undefined': lambda d: setting(d, 'fx.scale').update(Group='looks'),
  'bad-minmax-string': lambda d: setting(d, 'fx.scale').update(Minimum='small'),
  # dynamic Unset, so the loader's Unset.Value range check cannot catch it first
  'bad-min-gt-max': lambda d: setting(d, 'fx.scale').update(Minimum='2.5', Maximum='2.0',
                                                            Unset={'Behavior': 'dynamic', 'Help': 'Follows the desktop.'}),
  'bad-duplicate-key': lambda d: setting(d, 'fx.accent').update(Key='FxScale'),
  'bad-duplicate-enum-value': lambda d: setting(d, 'fx.scheme')['Values'].append({'Value': 'Dark'}),
  'bad-precedence-filter': lambda d: setting(d, 'fx.menu')['Precedence'][2].update(Values=['ribbon']),
  'bad-precedence-empty': lambda d: setting(d, 'fx.menu').update(Precedence=[]),
  'bad-case-insensitive': lambda d: setting(d, 'fx.scheme').update(CaseInsensitive='sometimes'),
  'bad-gstheme-key': lambda d: setting(d, 'fx.accent').update(Key='GSTheme'),
  'warn-precedence-unreachable': lambda d: setting(d, 'fx.menu')['Precedence'].append('application'),
  'warn-unknown-key': lambda d: setting(d, 'fx.scale').update(Minumum='0.5'),
}

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'Tests', 'Fixtures', 'Schema')
os.makedirs(out, exist_ok=True)
for name, fn in V.items():
    with open(os.path.join(out, name + '.plist'), 'w') as fh:
        fh.write('/* Generated by scripts/make-schema-fixtures.py: %s */\n' % name)
        fh.write(ser(variant(fn)) + '\n')
print('%d fixtures in %s' % (len(V), os.path.normpath(out)))
