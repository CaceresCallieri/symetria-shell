"""Exercise the portal protocol and the actual adapter process without a desktop."""

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

from scripts import screenshare_picker as picker

NAME = "Diseño[HE>]🪟"
OUTPUT = "屏:幕[HE>]🪟"


def field(text):
    return f"{len(text.encode())}:{text}"


def environment(output="eDP-1"):
    return {
        "XDPH_WINDOW_SHARING_LIST": "4294967295[HC>]app[HT>]Test window[HE>]9007199254740993[HA>]",
        "XDPH_OUTPUT_SHARING_LIST": f"{field(output)}:-1920:0:2560:1600;",
        "XDPH_WORKSPACE_SHARING_LIST_V3": f"18446744073709551615[HN>]{field(NAME)}[HM>]1:{field(output)}[HE>]",
    }


def test_opaque_ids_unicode_and_exact_address_matching():
    clients = [
        {"address": "9007199254740992", "stableId": "wrong"},
        {
            "address": "9007199254740993",
            "stableId": "exact",
            "workspace": {"name": NAME},
        },
    ]
    context = picker.create_context(environment(OUTPUT), clients, [], True)
    assert context["sources"]["windows"][0]["capture"] == ["-T", "exact"]
    assert context["sources"]["workspaces"][0]["app"] == "1 ventana"
    assert context["outputs"][0]["name"] == OUTPUT
    assert context["rememberDefault"] is True
    for mode, identifier, expected in [
        ("windows", "window:4294967295", "window:4294967295"),
        ("screens", "screen:" + OUTPUT, "screen:" + OUTPUT),
        (
            "workspaces",
            "workspace:18446744073709551615",
            "workspace-id:18446744073709551615",
        ),
    ]:
        assert (
            picker.serialize_selection(
                context, {"mode": mode, "id": identifier, "remember": True}
            )
            == f"[SELECTION]r/{expected}\n"
        )


@pytest.mark.parametrize("value", ["3:ab", "100:a:0:0:1:1;", "1:a:0:0:0:1;"])
def test_reject_invalid_output_fields(value):
    with pytest.raises((ValueError, UnicodeDecodeError)):
        picker.parse_outputs(value)


@pytest.mark.parametrize("identifier", ["0", str(2**64), "-1"])
def test_reject_invalid_workspace_ids(identifier):
    with pytest.raises(ValueError):
        picker.parse_workspaces(f"{identifier}[HN>]1:a[HM>]0:[HE>]")


def test_region_uses_logical_geometry_and_half_up_rounding():
    context = picker.create_context(environment(), [], [])
    request = {
        "mode": "region",
        "output": "eDP-1",
        "remember": False,
        "region": {"x": 0.1, "y": 0.2, "width": 0.5, "height": 0.5},
    }
    assert (
        picker.serialize_selection(context, request)
        == "[SELECTION]/region:eDP-1@256,320,1280,800\n"
    )
    context["outputs"][0]["width"] = 5
    request["region"] = {"x": 0.1, "y": 0, "width": 0.5, "height": 1}
    assert "@1,0,3,1600" in picker.serialize_selection(context, request)


@pytest.mark.parametrize(
    "change",
    [
        {"id": "window:foreign"},
        {"remember": 1},
        {"mode": "bogus"},
        {"mode": "region", "output": "other", "region": {}},
        {
            "mode": "region",
            "output": "eDP-1",
            "region": {"x": -0.1, "y": 0, "width": 1, "height": 1},
        },
        {
            "mode": "region",
            "output": "eDP-1",
            "region": {"x": 0, "y": 0, "width": float("nan"), "height": 1},
        },
        {
            "mode": "region",
            "output": "eDP-1",
            "region": {"x": True, "y": 0, "width": 1, "height": 1},
        },
    ],
)
def test_reject_unissued_and_invalid_selections(change):
    context = picker.create_context(environment(), [], [])
    with pytest.raises(ValueError):
        picker.serialize_selection(
            context,
            {"mode": "windows", "id": "window:4294967295", "remember": False, **change},
        )


def test_parent_placement_is_clamped_to_monitor_work_area():
    monitor = {
        "id": 1,
        "name": "test",
        "focused": True,
        "width": 2560,
        "height": 1600,
        "scale": 1,
        "transform": 0,
        "reserved": [0, 30, 0, 0],
        "x": 0,
        "y": 0,
    }
    assert picker.placement(
        [monitor], {"mapped": True, "monitor": 1, "at": [0, 0], "size": [1920, 1200]}
    ) == {"monitor": "test", "x": 96, "y": 60, "width": 1728, "height": 1080}
    monitor["transform"] = 1
    value = picker.placement([monitor], {})
    assert value["width"] <= 1600
    assert value["y"] >= 30


BROKER = """import json, socket, sys
path,token,mode,report=sys.argv[1:]
with socket.socket(socket.AF_UNIX) as connection:
 connection.connect(path)
 file=connection.makefile("rwb",buffering=0)
 context=json.loads(file.readline())
 assert context["token"]==token
 assert all(source["thumbnail"].startswith("file:") for source in context["context"]["sources"]["screens"])
 def send(message): file.write((json.dumps({"token":token,**message})+"\\n").encode())
 if mode=="disconnect": sys.exit(0)
 if mode=="bad-token":
  file.write(b'{"type":"cancel","token":"foreign"}\\n')
  sys.exit(0)
 if mode=="cancel": send({"type":"cancel"})
 else:
  send({"type":"confirm","mode":"windows","id":"window:foreign","remember":False})
  assert json.loads(file.readline())["type"]=="error"
  request={"type":"confirm","mode":mode,"remember":mode=="windows"}
  request["id"]={"windows":"window:4294967295","screens":"screen:eDP-1","workspaces":"workspace:18446744073709551615"}.get(mode,"")
  if mode=="region": request.update(output="eDP-1",region={"x":.1,"y":.2,"width":.5,"height":.5})
  send(request)
 assert json.loads(file.readline())["type"]=="done"
 open(report,"w").write(json.dumps({"context":context["context"],"passed":True}))
"""


@pytest.mark.parametrize(
    "mode,expected",
    [
        ("windows", "[SELECTION]r/window:4294967295\n"),
        ("screens", "[SELECTION]/screen:eDP-1\n"),
        ("workspaces", "[SELECTION]/workspace-id:18446744073709551615\n"),
        ("region", "[SELECTION]/region:eDP-1@256,320,1280,800\n"),
        ("cancel", ""),
        ("disconnect", ""),
        ("bad-token", ""),
    ],
)
def test_actual_adapter_cli(tmp_path, mode, expected):
    # Keep AF_UNIX paths below Linux's 108-byte limit, even under long pytest roots.
    import tempfile

    with tempfile.TemporaryDirectory(prefix="share-test-") as temporary:
        root = Path(temporary)
        binary = root / "bin"
        binary.mkdir()
        broker = root / "broker.py"
        broker.write_text(BROKER)
        report = root / "report.json"
        monitor = {
            "id": 0,
            "name": "eDP-1",
            "focused": True,
            "width": 2560,
            "height": 1600,
            "scale": 1,
            "transform": 0,
            "reserved": [0, 0, 0, 0],
            "x": 0,
            "y": 0,
        }
        commands = {
            "hyprctl": f"import json,sys\nprint(json.dumps({{'monitors':[{monitor!r}],'clients':[],'activewindow':{{}}}}[sys.argv[1]]))",
            "grim": "import sys,pathlib\npathlib.Path(sys.argv[-1]).write_bytes(b'preview fixture')",
            "qs": f"import subprocess,sys\nsubprocess.Popen([{sys.executable!r},{str(broker)!r},sys.argv[-2],sys.argv[-1],{mode!r},{str(report)!r}],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)\nprint('accepted')",
        }
        for name, body in commands.items():
            executable = binary / name
            executable.write_text(f"#!{sys.executable}\n{body}\n")
            executable.chmod(0o755)
        # Only the current Python and fixture executables run in this isolated PATH.
        result = subprocess.run(  # noqa: S603
            [sys.executable, str(Path(picker.__file__)), "--allow-token"],
            capture_output=True,
            text=True,
            timeout=15,
            env={
                **os.environ,
                **environment(),
                "XDG_RUNTIME_DIR": str(root),
                "PATH": str(binary) + os.pathsep + os.environ["PATH"],
            },
        )
        assert result.stdout == expected
        assert result.returncode == (1 if mode == "bad-token" else 0), result.stderr
        if mode == "bad-token":
            assert "Invalid screen-sharing request token" in result.stderr
        assert not list(root.glob("symmetria-share-*"))
        if mode not in ("disconnect", "bad-token"):
            observed = json.loads(report.read_text())
            assert observed["passed"]
            assert observed["context"]["rememberDefault"]


def test_qml_keyboard_and_region_components():
    runner = Path("/usr/lib/qt6/bin/qmltestrunner")
    if not runner.exists():
        pytest.skip("Qt6 qmltestrunner is unavailable")
    # The runner path is the installed Qt6 test executable.
    result = subprocess.run(  # noqa: S603
        [
            str(runner),
            "-platform",
            "offscreen",
            "-input",
            str(Path(__file__).with_name("qml")),
            "-o",
            "-,txt",
        ],
        capture_output=True,
        text=True,
        timeout=30,
        env={
            **os.environ,
            "QT_QPA_PLATFORM": "offscreen",
            "QT_QUICK_BACKEND": "software",
        },
    )
    assert result.returncode == 0, result.stdout + result.stderr
