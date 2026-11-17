//! UI-specific build configuration layered over the shared native environment.
const options = @import("build_options");
const native = @import("zenit_native_environment");

pub const enabled = native.enabled;
pub const getRaw = native.getRaw;
pub const getNative = native.getNative;
pub const has = native.has;
pub const flag = native.flag;
pub const getBorrowed = native.getBorrowed;
pub const GetError = native.GetError;
pub const getOwned = native.getOwned;
pub const getSystemOwned = native.getSystemOwned;

pub const lp3b_measure = @hasDecl(options, "lp3b_measure") and options.lp3b_measure;
pub const lp3b_template = @hasDecl(options, "lp3b_template") and options.lp3b_template;
pub const dev_preview = @hasDecl(options, "dev_preview") and options.dev_preview;
/// Web DOM host build: enables the renderer host seam in release wasm graphs.
pub const web_host = @import("builtin").cpu.arch.isWasm();
pub const lp2_gate = @hasDecl(options, "lp2_gate") and options.lp2_gate;
pub const lp4_gate = @hasDecl(options, "lp4_gate") and options.lp4_gate;
pub const lp3_gate = @hasDecl(options, "lp3_gate") and options.lp3_gate;
/// Test knob `-Dtext-inline-lines`: inline line capacity of a TextLayout (0 = default 1024).
pub const text_inline_lines: usize = if (@hasDecl(options, "text_inline_lines")) options.text_inline_lines else 0;

/// Parsers are absent from production release graphs. Repository fixture
/// adapters are exposed only to their explicit LP2/LP3 test graphs.
pub const preview = if (dev_preview or lp3_gate) struct {
    pub const compiler = @import("zenit_yss_compiler");
    pub const yix = compiler.preview_yix;
    pub const token_resolver = @import("zenit_token_resolver");
    pub const token_model = @import("zenit_token_model");
    pub const fixture4 = if (lp4_gate) @import("lp4_fixture") else struct {};
    pub const fixtures = if (lp3_gate) @import("lp3_fixtures") else if (lp2_gate) @import("lp2_fixtures") else struct {};
} else struct {};
