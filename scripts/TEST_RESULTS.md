# Plan A test results

## Environment
- Scripts: `run_test_a.sh` / `run_test_a_headless.sh`
- Map: default project `rm_navigation_ws/src/rm_nav_bringup/map/RMUL.yaml` (RMUL university league field)
- Nav2 params: `/home/nyu/nav_ws/my_nav2_params.yaml` ✓

## Findings

### 1. `~/.ros` permissions
`~/.ros` owned by root prevents ROS nodes from writing logs:

```
[ERROR] ... could not create log file ...
```

**Fix:**

```bash
sudo chown -R $(whoami):$(whoami) ~/.ros
```

### 2. RViz needs a display
Running in a headless terminal errors:

```
qt.qpa.xcb: could not connect to display
```

Use a desktop session for `run_test_a.sh`.

### 3. Nav2 `map_server` lifecycle failure
With `run_test_a_headless.sh`, `map_server` failed during configure:

```
[map_server-1] failed to change state
```

So `navigate_to_pose` action server is missing and the decision tree errors.

### 4. Components that worked
- ✓ Fake sensors (`fake_sensors_for_test.py`) publish `/scan`, `/odom`, TF
- ✓ Decision behavior tree loads and subscribes to `game_status`
- ✓ `game_status` publishes (game_progress=4)

## Suggested order

### Full test (with RViz)
1. Fix permissions: `sudo chown -R $(whoami):$(whoami) ~/.ros`
2. In a **terminal with a display**, run:

```bash
cd /path/to/sentry_planner/scripts
./run_test_a.sh
```

3. In RViz use "Nav2 Goal" to send a goal

### Headless quick check
Use the headless script (uses `/tmp` if `~/.ros` is not writable):

```bash
./run_test_a_headless.sh
```

Note: `map_server` may still fail; check Nav2 parameter wiring.

## Related files
- `run_test_a.sh` — full run (includes RViz)
- `run_test_a_headless.sh` — headless
- `fake_sensors_for_test.py` — fake sensors
