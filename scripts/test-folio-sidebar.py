#!/usr/bin/env python3
"""Exercise the live sidebar's integration boundary after a DMS upgrade."""
import json
import subprocess
import time


def ipc(*args):
    return subprocess.check_output(['dms', 'ipc', 'call', 'folioSidebar', *args], text=True).strip()


def status():
    return json.loads(ipc('status'))


def wait_for(predicate, timeout=5):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        state = status()
        if predicate(state):
            return state
        time.sleep(.1)
    raise AssertionError(f'Sidebar did not reach expected state: {state}')


def main():
    expected = {'sound': 'sound', 'world': 'worldClock', 'layout': 'workspaceModes', 'focus': 'focus',
                'battery': 'batteryLimit', 'codex': 'codexBar', 'notifications': 'notifications'}
    try:
        for section, plugin in expected.items():
            assert ipc('section', section) == section
            state = wait_for(lambda s: s['open'] and s['section'] == section and s['panels'].get(plugin))
            assert state['screen'], 'The drawer has no display'
            print(f'{section}: loaded on {state["screen"]}')
        before = status()['section']
        assert ipc('section', 'invalid') == 'ERROR: unknown section'
        assert status()['section'] == before
        ipc('close')
        wait_for(lambda s: not s['open'])
        ipc('toggle')
        wait_for(lambda s: s['open'])
        ipc('toggle')
        wait_for(lambda s: not s['open'])
        print('All sidebar integration checks passed.')
    finally:
        ipc('close')


if __name__ == '__main__':
    main()
