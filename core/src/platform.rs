//! Per-platform window behaviour.
//!
//! Everything Notchly needs from a window — transparency, floating above other apps,
//! and not stealing focus — sits below what Tauri exposes, so each platform reaches
//! into its own native window handle here.

use tauri::WebviewWindow;

#[cfg(target_os = "macos")]
mod imp {
    use objc2::rc::Retained;
    use objc2::runtime::{AnyObject, Bool};
    use objc2::{class, msg_send};
    use tauri::WebviewWindow;

    /// Level 25 is `NSStatusWindowLevel`: above ordinary windows and the menu bar.
    const STATUS_WINDOW_LEVEL: isize = 25;
    /// `canJoinAllSpaces | fullScreenAuxiliary | stationary | ignoresCycle`.
    const COLLECTION_BEHAVIOR: usize = 1 | (1 << 8) | (1 << 4) | (1 << 6);

    fn ns_window(window: &WebviewWindow) -> Option<*mut AnyObject> {
        window.ns_window().ok().map(|ptr| ptr as *mut AnyObject)
    }

    pub fn configure_panel(window: &WebviewWindow) {
        let Some(handle) = ns_window(window) else { return };
        unsafe {
            let _: () = msg_send![handle, setOpaque: Bool::NO];
            let clear: Retained<AnyObject> = msg_send![class!(NSColor), clearColor];
            let _: () = msg_send![handle, setBackgroundColor: &*clear];
            let _: () = msg_send![handle, setHasShadow: Bool::NO];
            let _: () = msg_send![handle, setLevel: STATUS_WINDOW_LEVEL];
            let _: () = msg_send![handle, setCollectionBehavior: COLLECTION_BEHAVIOR];
            // The panel is an accessory surface, never a document window.
            let _: () = msg_send![handle, setExcludedFromWindowsMenu: Bool::YES];
        }
    }


    /// Samples the window's own pixels. `(0.05, 0.5)` lands in the margin we leave for
    /// the shadow and must be fully transparent; `(0.9, 0.5)` lands inside the panel
    /// body and must be opaque.
    pub fn sample_transparency(window: &WebviewWindow) -> serde_json::Value {
        use core_graphics::display::{
            kCGWindowImageBoundsIgnoreFraming, kCGWindowListOptionIncludingWindow,
            CGDisplay, CGRect,
        };

        let Ok(window_id) = window_number(window) else {
            return serde_json::json!({ "error": "no window number" });
        };

        let image = CGDisplay::screenshot(
            CGRect::new(
                &core_graphics::geometry::CGPoint::new(f64::INFINITY, f64::INFINITY),
                &core_graphics::geometry::CGSize::new(0.0, 0.0),
            ),
            kCGWindowListOptionIncludingWindow,
            window_id as u32,
            kCGWindowImageBoundsIgnoreFraming,
        );

        let Some(image) = image else {
            return serde_json::json!({ "error": "window capture returned nothing" });
        };

        let width = image.width();
        let height = image.height();
        let bytes_per_row = image.bytes_per_row();
        let bits_per_pixel = image.bits_per_pixel();
        let data = image.data();
        let bytes: &[u8] = &data;

        if bits_per_pixel != 32 || width == 0 || height == 0 {
            return serde_json::json!({
                "error": format!("unexpected image format: {bits_per_pixel}bpp {width}x{height}")
            });
        }

        // BGRA, alpha last byte of each pixel.
        let alpha_at = |fx: f64, fy: f64| -> Option<u8> {
            let x = (fx * width as f64) as usize;
            let y = (fy * height as f64) as usize;
            let index = y * bytes_per_row + x * 4 + 3;
            bytes.get(index).copied()
        };

        // Walk across the window. A correctly transparent window shows a clean
        // progression: nothing at the far edge, then the shadow fading in, then the
        // opaque panel body. A broken one is flat 255 the whole way across.
        let profile: Vec<u8> = (0..20)
            .map(|step| alpha_at(step as f64 / 20.0, 0.5).unwrap_or(0))
            .collect();

        let far_edge = alpha_at(0.002, 0.5).unwrap_or(255);
        let inside = alpha_at(0.90, 0.5).unwrap_or(0);

        serde_json::json!({
            "captured": true,
            "width": width,
            "height": height,
            "alphaProfileLeftToRight": profile,
            "alphaAtFarEdge": far_edge,
            "alphaInsideShape": inside,
            // The far edge sits outside the panel and outside its shadow, so it must be
            // fully clear; the body must be painted.
            "transparencyProven": far_edge == 0 && inside > 200
        })
    }

    /// Writes the panel's own window to a PNG, alpha intact.
    ///
    /// Capturing your own window needs no Screen Recording permission, which makes this
    /// the only way to actually look at a surface that lives at the edge of the display.
    pub fn capture_png(window: &WebviewWindow, path: &str) -> serde_json::Value {
        use core_graphics::display::{
            kCGWindowImageBoundsIgnoreFraming, kCGWindowListOptionIncludingWindow, CGDisplay,
            CGRect,
        };

        let Ok(window_id) = window_number(window) else {
            return serde_json::json!({ "error": "no window number" });
        };
        let image = CGDisplay::screenshot(
            CGRect::new(
                &core_graphics::geometry::CGPoint::new(f64::INFINITY, f64::INFINITY),
                &core_graphics::geometry::CGSize::new(0.0, 0.0),
            ),
            kCGWindowListOptionIncludingWindow,
            window_id as u32,
            kCGWindowImageBoundsIgnoreFraming,
        );
        let Some(image) = image else {
            return serde_json::json!({ "error": "capture returned nothing" });
        };

        let (width, height) = (image.width(), image.height());
        let stride = image.bytes_per_row();
        let data = image.data();
        let bytes: &[u8] = &data;

        // CoreGraphics hands back BGRA with its own row padding; PNG wants tight RGBA.
        let mut rgba = Vec::with_capacity(width * height * 4);
        for y in 0..height {
            for x in 0..width {
                let i = y * stride + x * 4;
                match bytes.get(i..i + 4) {
                    Some(px) => rgba.extend_from_slice(&[px[2], px[1], px[0], px[3]]),
                    None => rgba.extend_from_slice(&[0, 0, 0, 0]),
                }
            }
        }

        match image::RgbaImage::from_raw(width as u32, height as u32, rgba) {
            Some(buffer) => match buffer.save(path) {
                Ok(()) => serde_json::json!({ "saved": path, "width": width, "height": height }),
                Err(error) => serde_json::json!({ "error": error.to_string() }),
            },
            None => serde_json::json!({ "error": "buffer size mismatch" }),
        }
    }

    fn window_number(window: &WebviewWindow) -> Result<isize, ()> {
        let Some(handle) = ns_window(window) else { return Err(()) };
        unsafe { Ok(msg_send![handle, windowNumber]) }
    }

    /// Reads the window back after configuration, so the spike reports what the system
    /// actually did rather than what we asked for.
    pub fn describe_window(window: &WebviewWindow) -> serde_json::Value {
        let Some(handle) = ns_window(window) else {
            return serde_json::json!({ "error": "no ns_window" });
        };
        unsafe {
            let opaque: Bool = msg_send![handle, isOpaque];
            let has_shadow: Bool = msg_send![handle, hasShadow];
            let level: isize = msg_send![handle, level];
            let background: Retained<AnyObject> = msg_send![handle, backgroundColor];
            let alpha: f64 = msg_send![&*background, alphaComponent];

            // The reported failure mode is the *web view* painting an opaque background
            // even when the window is transparent, so inspect the content layer too.
            let content_view: Retained<AnyObject> = msg_send![handle, contentView];
            let view_opaque: Bool = msg_send![&*content_view, isOpaque];
            let layer: *mut AnyObject = msg_send![&*content_view, layer];
            let layer_opaque = if layer.is_null() {
                serde_json::Value::Null
            } else {
                let value: Bool = msg_send![layer, isOpaque];
                serde_json::Value::Bool(value.as_bool())
            };

            serde_json::json!({
                "platform": "macos",
                "windowOpaque": opaque.as_bool(),
                "backgroundAlpha": alpha,
                "hasShadow": has_shadow.as_bool(),
                "level": level,
                "contentViewOpaque": view_opaque.as_bool(),
                "contentLayerOpaque": layer_opaque,
                "transparencyLooksCorrect":
                    !opaque.as_bool() && alpha == 0.0 && !view_opaque.as_bool()
            })
        }
    }
}

#[cfg(target_os = "windows")]
mod imp {
    use tauri::WebviewWindow;

    pub fn configure_panel(_window: &WebviewWindow) {
        // Phase 1: WS_EX_NOACTIVATE | WS_EX_TOPMOST via windows-rs.
    }

    pub fn describe_window(_window: &WebviewWindow) -> serde_json::Value {
        serde_json::json!({ "platform": "windows", "transparencyLooksCorrect": null })
    }
    pub fn sample_transparency(_window: &WebviewWindow) -> serde_json::Value {
        serde_json::json!({ "captured": false })
    }

    pub fn capture_png(_window: &WebviewWindow, _path: &str) -> serde_json::Value {
        serde_json::json!({ "error": "capture is macOS only" })
    }

}

#[cfg(not(any(target_os = "macos", target_os = "windows")))]
mod imp {
    use tauri::WebviewWindow;

    pub fn configure_panel(_window: &WebviewWindow) {}

    pub fn describe_window(_window: &WebviewWindow) -> serde_json::Value {
        serde_json::json!({ "platform": "other", "transparencyLooksCorrect": null })
    }
    pub fn sample_transparency(_window: &WebviewWindow) -> serde_json::Value {
        serde_json::json!({ "captured": false })
    }

    pub fn capture_png(_window: &WebviewWindow, _path: &str) -> serde_json::Value {
        serde_json::json!({ "error": "capture is macOS only" })
    }

}

pub fn configure_panel(window: &WebviewWindow) {
    imp::configure_panel(window)
}

pub fn describe_window(window: &WebviewWindow) -> serde_json::Value {
    imp::describe_window(window)
}

/// Reads the alpha channel of the panel's own window back from the window server.
///
/// This is the only test that actually proves transparency: the window can report
/// itself as non-opaque while the web view underneath still paints a solid
/// background. Capturing our *own* window needs no Screen Recording permission.
pub fn sample_transparency(window: &WebviewWindow) -> serde_json::Value {
    imp::sample_transparency(window)
}

/// Saves a PNG of the panel window. A development aid — the panel only ever appears at
/// the edge of a live display, which makes it awkward to inspect any other way.
pub fn capture_png(window: &WebviewWindow, path: &str) -> serde_json::Value {
    imp::capture_png(window, path)
}
