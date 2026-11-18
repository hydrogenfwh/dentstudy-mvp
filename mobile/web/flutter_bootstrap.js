{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  // iOS Safari can advertise enough WebAssembly support for Flutter to pick
  // dart2wasm, then fail while importing its ES-module support runtime. Keep
  // WebKit on the mature CanvasKit/JavaScript build instead. Chromium may
  // still select the faster Wasm build when it is actually compatible.
  config: {wasmAllowList: {webkit: false}},
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}}
  }
});
