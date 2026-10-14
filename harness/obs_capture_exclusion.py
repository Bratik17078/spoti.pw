"""A private Windows Tkinter assistant window.

Select text anywhere, then press Ctrl+Shift+F8. The selected text is read from
the clipboard and sent to an OpenAI-compatible Chat Completions endpoint. The
answer is shown in this window, which asks Windows to omit it from compatible
screen-capture APIs. It is not DRM and cannot block every capture method.
"""

import ctypes
from ctypes import wintypes
import json
import os
from queue import Empty, Queue
import sys
import threading
import tkinter as tk
from tkinter import scrolledtext
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


WDA_EXCLUDEFROMCAPTURE = 0x00000011

# Global shortcut: Ctrl+Shift+F8. Change these constants if this combination
# is already used by another application.
HOTKEY_ID = 1
WM_HOTKEY = 0x0312
WM_QUIT = 0x0012
MOD_CONTROL = 0x0002
MOD_SHIFT = 0x0004
MOD_NOREPEAT = 0x4000
VK_F8 = 0x77
VK_CONTROL = 0x11
VK_C = 0x43
KEYEVENTF_KEYUP = 0x0002


def exclude_from_capture(window: tk.Tk) -> None:
    """Ask Windows not to include this top-level window in screen captures."""
    user32 = ctypes.WinDLL("user32", use_last_error=True)
    get_ancestor = user32.GetAncestor
    get_ancestor.argtypes = (ctypes.c_void_p, ctypes.c_uint)
    get_ancestor.restype = ctypes.c_void_p

    # Tk's ID can be its client window. The Windows API requires the top-level
    # HWND, so resolve the root window first.
    top_level_hwnd = get_ancestor(window.winfo_id(), 2)  # GA_ROOT
    if not top_level_hwnd:
        error = ctypes.get_last_error()
        raise OSError(error, ctypes.FormatError(error))

    set_affinity = user32.SetWindowDisplayAffinity
    set_affinity.argtypes = (ctypes.c_void_p, ctypes.c_uint)
    set_affinity.restype = ctypes.c_bool
    if not set_affinity(top_level_hwnd, WDA_EXCLUDEFROMCAPTURE):
        error = ctypes.get_last_error()
        raise OSError(
            error,
            f"{ctypes.FormatError(error)} (top-level HWND: 0x{top_level_hwnd:X})",
        )


class PrivateAssistant:
    def __init__(self, root: tk.Tk) -> None:
        self.root = root
        self.events: Queue[tuple[str, str | None]] = Queue()
        self.request_in_flight = False
        self.hotkey_thread_id: int | None = None

        root.title("Private assistant")
        root.wm_attributes("-toolwindow", True)  # no normal taskbar button
        root.geometry("620x430+80+80")
        root.configure(background="#17151f")
        root.protocol("WM_DELETE_WINDOW", self.close)
        root.bind("<Escape>", lambda _event: self.close())

        tk.Label(
            root,
            text="Private assistant",
            foreground="#f5f1ff",
            background="#17151f",
            font=("Segoe UI", 18, "bold"),
        ).pack(anchor="w", padx=18, pady=(18, 3))
        self.status = tk.StringVar(value="Select text, then press Ctrl+Shift+F8.")
        tk.Label(
            root,
            textvariable=self.status,
            foreground="#c9c3d4",
            background="#17151f",
            font=("Segoe UI", 10),
        ).pack(anchor="w", padx=18, pady=(0, 12))
        self.response = scrolledtext.ScrolledText(
            root,
            wrap="word",
            background="#25212f",
            foreground="#f5f1ff",
            insertbackground="#f5f1ff",
            relief="flat",
            font=("Segoe UI", 11),
            padx=12,
            pady=12,
        )
        self.response.pack(fill="both", expand=True, padx=18, pady=(0, 18))
        self._write_response("The API response will appear here.")

        root.update_idletasks()
        exclude_from_capture(root)
        threading.Thread(target=self._hotkey_loop, daemon=True).start()
        root.after(75, self._drain_events)

    def _write_response(self, text: str) -> None:
        self.response.configure(state="normal")
        self.response.delete("1.0", "end")
        self.response.insert("1.0", text)
        self.response.configure(state="disabled")

    def _hotkey_loop(self) -> None:
        """Receive the global hotkey on a dedicated Windows message loop."""
        user32 = ctypes.WinDLL("user32", use_last_error=True)
        register = user32.RegisterHotKey
        register.argtypes = (wintypes.HWND, ctypes.c_int, ctypes.c_uint, ctypes.c_uint)
        register.restype = wintypes.BOOL
        unregister = user32.UnregisterHotKey
        unregister.argtypes = (wintypes.HWND, ctypes.c_int)
        get_message = user32.GetMessageW
        get_message.argtypes = (
            ctypes.POINTER(wintypes.MSG),
            wintypes.HWND,
            wintypes.UINT,
            wintypes.UINT,
        )
        get_message.restype = ctypes.c_int

        self.hotkey_thread_id = threading.get_native_id()
        modifiers = MOD_CONTROL | MOD_SHIFT | MOD_NOREPEAT
        if not register(None, HOTKEY_ID, modifiers, VK_F8):
            error = ctypes.get_last_error()
            self.events.put(("error", f"Could not register Ctrl+Shift+F8: {ctypes.FormatError(error)}"))
            return

        try:
            message = wintypes.MSG()
            while get_message(ctypes.byref(message), None, 0, 0) > 0:
                if message.message == WM_HOTKEY:
                    self.events.put(("hotkey", None))
        finally:
            unregister(None, HOTKEY_ID)

    def _drain_events(self) -> None:
        try:
            while True:
                event, payload = self.events.get_nowait()
                if event == "hotkey":
                    self._copy_then_submit_selection()
                elif event == "response":
                    self.request_in_flight = False
                    self.status.set("Ready — select text and press Ctrl+Shift+F8.")
                    self._write_response(payload or "")
                elif event == "error":
                    self.request_in_flight = False
                    self.status.set("Request failed.")
                    self._write_response(f"Error:\n{payload}")
        except Empty:
            pass
        if self.root.winfo_exists():
            self.root.after(75, self._drain_events)

    def _copy_then_submit_selection(self) -> None:
        """Copy the focused app's selection, then read the resulting clipboard."""
        self.status.set("Copying selected text…")
        user32 = ctypes.WinDLL("user32")
        keybd_event = user32.keybd_event
        keybd_event.argtypes = (ctypes.c_ubyte, ctypes.c_ubyte, ctypes.c_uint, ctypes.c_size_t)

        # A selection is not universally readable through Windows APIs. Sending
        # Ctrl+C to the still-focused application is the compatible route.
        keybd_event(VK_CONTROL, 0, 0, 0)
        keybd_event(VK_C, 0, 0, 0)
        keybd_event(VK_C, 0, KEYEVENTF_KEYUP, 0)
        keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, 0)
        # Give the foreground app a moment to own and populate the clipboard.
        self.root.after(120, self._submit_selection)

    def _submit_selection(self) -> None:
        if self.request_in_flight:
            self.status.set("A request is already running.")
            return
        try:
            selected_text = self.root.clipboard_get().strip()
        except tk.TclError:
            selected_text = ""
        if not selected_text:
            self.status.set("No text is available in the clipboard.")
            return

        self.request_in_flight = True
        self.status.set("Sending selected text…")
        self._write_response("Waiting for the API response…")
        threading.Thread(target=self._request_answer, args=(selected_text,), daemon=True).start()

    def _request_answer(self, selected_text: str) -> None:
        try:
            api_url = os.environ["PRIVATE_ASSISTANT_API_URL"]
            api_key = os.environ["PRIVATE_ASSISTANT_API_KEY"]
            model = os.environ["PRIVATE_ASSISTANT_MODEL"]
        except KeyError as missing:
            self.events.put(("error", f"Set {missing.args[0]} before starting the program."))
            return

        # This is the broadly supported OpenAI-compatible Chat Completions
        # request shape. Providers with a different protocol need an adapter
        # in this method and in _response_text below.
        payload = json.dumps(
            {
                "model": model,
                "messages": [{"role": "user", "content": selected_text}],
            }
        ).encode("utf-8")
        request = Request(
            api_url,
            data=payload,
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {api_key}",
            },
            method="POST",
        )
        try:
            with urlopen(request, timeout=60) as response:
                body = json.loads(response.read().decode("utf-8"))
            self.events.put(("response", self._response_text(body)))
        except HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")
            self.events.put(("error", f"HTTP {error.code}: {detail}"))
        except (URLError, TimeoutError, json.JSONDecodeError, ValueError) as error:
            self.events.put(("error", str(error)))

    @staticmethod
    def _response_text(body: dict) -> str:
        try:
            content = body["choices"][0]["message"]["content"]
        except (KeyError, IndexError, TypeError) as error:
            raise ValueError("The API returned an unexpected response shape.") from error
        if isinstance(content, str):
            return content
        if isinstance(content, list):
            return "".join(part.get("text", "") for part in content if isinstance(part, dict))
        raise ValueError("The API response content was not text.")

    def close(self) -> None:
        if self.hotkey_thread_id:
            ctypes.WinDLL("user32").PostThreadMessageW(self.hotkey_thread_id, WM_QUIT, 0, 0)
        self.root.destroy()


def main() -> None:
    if sys.platform != "win32":
        raise SystemExit("This program uses Windows-only APIs.")
    root = tk.Tk()
    try:
        PrivateAssistant(root)
    except OSError as error:
        root.destroy()
        raise SystemExit(f"Could not enable capture exclusion: {error}") from error
    root.mainloop()


if __name__ == "__main__":
    main()
