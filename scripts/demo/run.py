"""Runs a demo script as anonymous Apex and prints only what the script says.

    py scripts/demo/run.py 01          the script whose name starts with 01
    py scripts/demo/run.py play        scripts/demo/play.apex, the one to type into
    py scripts/demo/run.py seed        seed.apex; reset.apex the same way
    py scripts/demo/run.py some.apex   any file

    --all        print every debug line, not only the ones Demo.say wrote
    --org NAME   another org (the default is the project's, from .sf/config.json)

Lines written with Demo.say, Demo.table and the rest carry a marker in the debug log; those are
what is printed. A script that uses plain System.debug has all its debug lines printed instead.
"""
import glob
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.normpath(os.path.join(HERE, '..', '..'))
MARK = 'DEMO::'


def find(name):
    if os.path.isfile(name):
        return name
    for pattern in (name, name + '.apex', name + '*.apex'):
        hits = sorted(glob.glob(os.path.join(HERE, pattern)))
        if hits:
            return hits[0]
    sys.exit('No script matches ' + name + '. Scripts: ' + ', '.join(sorted(os.path.basename(p) for p in glob.glob(os.path.join(HERE, '*.apex')))))


def default_org():
    try:
        return json.load(open(os.path.join(PROJECT, '.sf', 'config.json'))).get('target-org')
    except (OSError, ValueError):
        return None


def debug_lines(log):
    """The text of each USER_DEBUG entry. A message of several lines continues on untimed lines."""
    out = []
    taking = False
    for line in log.splitlines():
        parts = line.split('|', 4)
        timed = len(parts) >= 2 and parts[0][:2].isdigit() and ':' in parts[0]
        if timed:
            taking = len(parts) == 5 and parts[1] == 'USER_DEBUG'
            if taking:
                out.append(parts[4].replace('&#124;', '|'))
        elif taking:
            out.append(line.replace('&#124;', '|'))
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    flags = sys.argv[1:]
    if not args:
        sys.exit(__doc__)
    show_all = '--all' in flags
    org = flags[flags.index('--org') + 1] if '--org' in flags else default_org()
    if '--org' in flags:
        args = [a for a in args if a != org]
    script = find(args[0])

    command = 'sf apex run --file "' + script + '" --json' + (' --target-org ' + org if org else '')
    done = subprocess.run(command, shell=True, capture_output=True, cwd=PROJECT)
    text = done.stdout.decode('utf-8', errors='replace')
    try:
        reply = json.loads(text[text.index('{'):])
    except ValueError:
        sys.exit('The command gave no result:\n' + text + done.stderr.decode('utf-8', errors='replace'))

    result = reply.get('result') or reply.get('data') or {}
    if not result:
        sys.exit(reply.get('message') or text)

    lines = debug_lines(result.get('logs') or '')
    marked = [line[len(MARK):] for line in lines if line.startswith(MARK)]
    shown = lines if show_all or not marked else marked
    print('\n'.join(shown).encode(sys.stdout.encoding or 'utf-8', errors='replace').decode(sys.stdout.encoding or 'utf-8'))

    if result.get('compiled') is False:
        sys.exit('\nDid not compile, line ' + str(result.get('line')) + ' column ' + str(result.get('column')) + ': ' + str(result.get('compileProblem')))
    if result.get('success') is False:
        sys.exit('\nStopped: ' + str(result.get('exceptionMessage')) + '\n' + str(result.get('exceptionStackTrace') or ''))


if __name__ == '__main__':
    main()
