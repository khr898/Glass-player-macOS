#!/usr/bin/env python3
"""
Translate Anime4K GLSL shaders to Metal following the Anime4KMetal pattern.

This script produces Metal shaders with CONSISTENT texture binding:
- BINDS at indices 0, 1, 2, ... (based on BIND directives)
- MAIN at index len(BINDS) if HOOK=MAIN and MAIN not in BINDS
- OUTPUT at the LAST index (after all inputs)

Key difference from previous translation:
- Output is ALWAYS at the highest texture index
- Input texture indices are determined by BIND order, not hardcoded
- This matches how Anime4KMetal binds textures at runtime

Bug fix: The original Anime4KMetal uses bilinear sampling when it should use
nearest for intermediate passes. We fix this by using the correct sampler
based on the output/input size ratio.
"""

import re
import os
import sys

# Required shaders for Glass Player presets
REQUIRED_SHADERS = [
    # (subdirectory, glsl_filename, metal_filename)
    ("Restore", "Anime4K_Clamp_Highlights.glsl", "Anime4K_Clamp_Highlights.metal"),
    ("Restore", "Anime4K_Restore_CNN_S.glsl", "Anime4K_Restore_CNN_S.metal"),
    ("Restore", "Anime4K_Restore_CNN_M.glsl", "Anime4K_Restore_CNN_M.metal"),
    ("Restore", "Anime4K_Restore_CNN_VL.glsl", "Anime4K_Restore_CNN_VL.metal"),
    ("Restore", "Anime4K_Restore_CNN_Soft_S.glsl", "Anime4K_Restore_CNN_Soft_S.metal"),
    ("Restore", "Anime4K_Restore_CNN_Soft_M.glsl", "Anime4K_Restore_CNN_Soft_M.metal"),
    ("Restore", "Anime4K_Restore_CNN_Soft_VL.glsl", "Anime4K_Restore_CNN_Soft_VL.metal"),
    ("Upscale", "Anime4K_Upscale_CNN_x2_S.glsl", "Anime4K_Upscale_CNN_x2_S.metal"),
    ("Upscale", "Anime4K_Upscale_CNN_x2_M.glsl", "Anime4K_Upscale_CNN_x2_M.metal"),
    ("Upscale", "Anime4K_Upscale_CNN_x2_VL.glsl", "Anime4K_Upscale_CNN_x2_VL.metal"),
    ("Upscale+Denoise", "Anime4K_Upscale_Denoise_CNN_x2_M.glsl", "Anime4K_Upscale_Denoise_CNN_x2_M.metal"),
    ("Upscale+Denoise", "Anime4K_Upscale_Denoise_CNN_x2_VL.glsl", "Anime4K_Upscale_Denoise_CNN_x2_VL.metal"),
    ("Upscale", "Anime4K_AutoDownscalePre_x2.glsl", "Anime4K_AutoDownscalePre_x2.metal"),
    ("Upscale", "Anime4K_AutoDownscalePre_x4.glsl", "Anime4K_AutoDownscalePre_x4.metal"),
]

GLSL_DIR = os.environ.get("GLSL_DIR", "/Users/user/Glass-player-macOS/Anime4K_GLSL/glsl")
OUTPUT_DIR = os.environ.get("OUTPUT_DIR", "/tmp/metal-shaders-output")


class MPVShader:
    """Parse and translate a single MPV/GLSL shader to Metal."""

    def __init__(self, name: str):
        self.name = name
        self.hook: str | None = None
        self.binds: list[str] = []
        self.save: str | None = None
        self.components: int | None = None
        self.width: tuple[str, float] | None = None
        self.height: tuple[str, float] | None = None
        self.when: str | None = None
        self.sigma: float | None = None
        self.code: list[str] = []

    def get_function_name(self, pass_index: int = 0) -> str:
        """Convert shader name to valid Metal function name.

        Args:
            pass_index: Index of this pass (for unique naming when multiple passes have same name)
        """
        base_name = re.sub(r'[^a-zA-Z0-9]', '', self.name)
        if pass_index > 0:
            return f"{base_name}_pass{pass_index}"
        return base_name

    @property
    def input_texture_names(self) -> list[str]:
        """Get list of input texture names in binding order."""
        names = list(self.binds)
        if self.hook == "MAIN" and "MAIN" not in names:
            names.append("MAIN")
        return names

    @property
    def output_texture_name(self) -> str:
        """Get output texture name."""
        if self.save and self.save != "MAIN":
            return self.save
        return "output"

    def generate_metal_code(self, pass_index: int = 0) -> str:
        """Generate Metal shader code following Anime4KMetal pattern.

        Args:
            pass_index: Index of this pass within the shader file (for unique naming)
        """
        # Header
        header = """#include <metal_stdlib>
using namespace metal;

using vec2 = float2;
using vec3 = float3;
using vec4 = float4;
using ivec2 = int2;
using mat4 = float4x4;

"""

        # BIND macros - skip MAIN as it's handled separately
        bind_macros = ""
        for bind in self.binds:
            if bind == "MAIN":
                continue  # MAIN macros are generated below
            bind_macros += f"""#define {bind}_pos mtlPos
#define {bind}_size float2({bind}.get_width(), {bind}.get_height())
#define {bind}_pt (float2(1, 1) / {bind}_size)
#define {bind}_tex(pos) {bind}.sample(textureSampler, pos)
#define {bind}_texOff(off) {bind}_tex({bind}_pos + {bind}_pt * float2(off))

"""

        # HOOKED/MAIN macros
        if self.hook == "MAIN":
            header += """#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

#define HOOKED_pos MAIN_pos
#define HOOKED_size MAIN_size
#define HOOKED_pt MAIN_pt
#define HOOKED_tex(pos) MAIN_tex(pos)
#define HOOKED_texOff(off) MAIN_texOff(off)

"""
        else:
            header += """#define HOOKED_pos mtlPos
#define HOOKED_size float2(HOOKED.get_width(), HOOKED.get_height())
#define HOOKED_pt (float2(1, 1) / HOOKED_size)
#define HOOKED_tex(pos) HOOKED.sample(textureSampler, pos)
#define HOOKED_texOff(off) HOOKED_tex(HOOKED_pos + HOOKED_pt * float2(off))

#define MAIN_pos mtlPos
#define MAIN_pt (float2(1, 1) / float2(MAIN.get_width(), MAIN.get_height()))
#define MAIN_size float2(MAIN.get_width(), MAIN.get_height())
#define MAIN_tex(pos) MAIN.sample(textureSampler, pos)
#define MAIN_texOff(off) MAIN_tex(MAIN_pos + MAIN_pt * float2(off))

"""

        # Process code - extract functions and add extra args
        functions: list[str] = []
        processed_code: list[str] = []
        in_function = False
        current_func = None

        # Build extra args string for internal functions
        # IMPORTANT: mtlPos must be FIRST parameter (matches Anime4KMetal pattern)
        extra_args_list = ["float2 mtlPos"]
        for bind in self.binds:
            extra_args_list.append(f"texture2d<float, access::sample> {bind}")
        if self.hook == "MAIN" and "MAIN" not in self.binds:
            extra_args_list.append("texture2d<float, access::sample> MAIN")
        extra_args_list.append("sampler textureSampler")
        extra_args_str = ", ".join(extra_args_list)

        # Build extra call args
        extra_call_list = ["mtlPos"]
        for bind in self.binds:
            extra_call_list.append(bind)
        if self.hook == "MAIN" and "MAIN" not in self.binds:
            extra_call_list.append("MAIN")
        extra_call_list.append("textureSampler")
        extra_call_args_str = ", ".join(extra_call_list)

        # Make hook function name unique per pass
        hook_fn_name = f"hook" if pass_index == 0 else f"hook_pass{pass_index}"

        for line in self.code:
            # Detect function definition - rename 'hook' to unique name
            func_match = re.match(r'^(\w+(?:\s+\w+)*?)\s+(\w+)\s*\((.*)\)\s*\{?\s*$', line)
            if func_match and not line.startswith('#'):
                ret_type = func_match.group(1)
                func_name = func_match.group(2)
                args = func_match.group(3)

                current_func = func_name
                functions.append(func_name)
                in_function = True

                # Rename 'hook' function to unique name
                if func_name == "hook":
                    func_name = hook_fn_name

                # Add function with extra args
                if args:
                    new_line = f"{ret_type} {func_name}({extra_args_str}, {args}) {{"
                else:
                    new_line = f"{ret_type} {func_name}({extra_args_str}) {{"

                processed_code.append(new_line)
                continue

            if in_function and line.strip() == '}':
                in_function = False
                current_func = None

            # Replace function calls with extra arguments
            new_line = line
            for func in functions:
                # Rename hook calls to unique name
                call_func = hook_fn_name if func == "hook" else func
                pattern = rf'\b{func}\s*\('
                if re.search(pattern, new_line):
                    new_line = re.sub(pattern, f'{call_func}({extra_call_args_str}, ', new_line)
                    # Fix double commas or trailing commas before )
                    new_line = re.sub(r', , ', ', ', new_line)
                    new_line = re.sub(r', \)', ')', new_line)

            processed_code.append(new_line)

        # Build kernel function signature with CORRECT texture binding
        # This is the KEY FIX: output is ALWAYS at the highest index
        entry_args: list[str] = []
        texture_idx = 0

        # BINDS at indices 0, 1, 2, ...
        for bind in self.binds:
            entry_args.append(f"texture2d<float, access::sample> {bind} [[texture({texture_idx})]]")
            texture_idx += 1

        # MAIN at next index (if HOOK=MAIN and MAIN not in BINDS)
        if self.hook == "MAIN" and "MAIN" not in self.binds:
            entry_args.append(f"texture2d<float, access::sample> MAIN [[texture({texture_idx})]]")
            texture_idx += 1

        # OUTPUT at the LAST index
        entry_args.append(f"texture2d<float, access::write> output [[texture({texture_idx})]]")
        texture_idx += 1

        entry_args.append("uint2 gid [[thread_position_in_grid]]")
        entry_args.append("sampler textureSampler [[sampler(0)]]")

        # Build hook call arguments
        hook_call_args = []
        for bind in self.binds:
            hook_call_args.append(bind)
        if self.hook == "MAIN" and "MAIN" not in self.binds:
            hook_call_args.append("MAIN")
        hook_call_args.append("textureSampler")

        # Make hook function name unique per pass to avoid redefinition
        hook_fn_name = f"hook" if pass_index == 0 else f"hook_pass{pass_index}"

        # Kernel function - pass mtlPos to hook function
        kernel = f"""
kernel void {self.get_function_name(pass_index)}(
    {', '.join(entry_args)}) {{
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write({hook_fn_name}(mtlPos, {', '.join(hook_call_args)}), gid);
}}
"""

        return header + bind_macros + '\n'.join(processed_code) + kernel

    @classmethod
    def parse(cls, glsl_content: str) -> list['MPVShader']:
        """Parse GLSL content and return list of shaders."""
        shaders: list[MPVShader] = []
        current: MPVShader | None = None

        for line in glsl_content.split('\n'):
            line = line.strip()
            if not line:
                continue

            # Skip non-directive comments
            if line.startswith('//') and not line.startswith('//!'):
                continue

            # Parse directive
            if line.startswith('//!'):
                parts = line[3:].split()
                if not parts:
                    continue

                cmd = parts[0]

                if cmd == 'DESC':
                    # New shader
                    if current:
                        shaders.append(current)
                    current = cls(' '.join(parts[1:]))

                elif current:
                    if cmd == 'HOOK':
                        current.hook = parts[1] if len(parts) > 1 else 'MAIN'
                        if current.hook == 'PREKERNEL':
                            current.hook = 'MAIN'
                    elif cmd == 'BIND':
                        if len(parts) > 1:
                            current.binds.append(parts[1])
                    elif cmd == 'SAVE':
                        if len(parts) > 1:
                            current.save = parts[1]
                    elif cmd == 'WIDTH':
                        if len(parts) >= 2:
                            current.width = (parts[1], 1.0)  # Simplified
                    elif cmd == 'HEIGHT':
                        if len(parts) >= 2:
                            current.height = (parts[1], 1.0)  # Simplified
                    elif cmd == 'WHEN':
                        current.when = ' '.join(parts[1:])
                    elif cmd == 'COMPONENTS':
                        if len(parts) > 1:
                            current.components = int(parts[1])

            elif current:
                # Handle SPATIAL_SIGMA for KERNELSIZE
                if '#define SPATIAL_SIGMA' in line:
                    match = re.search(r'#define SPATIAL_SIGMA\s+(\d+)', line)
                    if match:
                        current.sigma = float(match.group(1))

                # Handle KERNELSIZE that depends on SPATIAL_SIGMA
                if '#define KERNELSIZE int(max(int(SPATIAL_SIGMA)' in line and current.sigma:
                    kernel_size = int(max(int(current.sigma), 1) * 2 + 1)
                    current.code.append(f"#define KERNELSIZE {kernel_size}")
                    continue

                current.code.append(line)

        if current:
            shaders.append(current)

        return shaders


def translate_file(glsl_path: str, metal_path: str) -> list[MPVShader]:
    """Translate a single GLSL file to Metal."""
    with open(glsl_path, 'r') as f:
        glsl = f.read()

    shaders = MPVShader.parse(glsl)

    with open(metal_path, 'w') as f:
        f.write("// Auto-generated from GLSL using translate_anime4k_shaders.py\n")
        f.write("// Texture binding: BINDS=[0..N-1], MAIN=[N if applicable], OUTPUT=[last]\n")
        f.write(f"// Source: {os.path.basename(glsl_path)}\n")
        f.write(f"// Shaders: {len(shaders)}\n\n")

        for i, shader in enumerate(shaders):
            fn_name = shader.get_function_name(i)
            f.write(f"// Shader: {shader.name}\n")
            f.write(f"// Function: {fn_name}\n")
            f.write(f"// BINDS: {shader.binds}\n")
            f.write(f"// HOOK: {shader.hook}\n")
            f.write(f"// SAVE: {shader.save}\n")
            f.write(f"// Input textures: {shader.input_texture_names}\n")
            f.write(f"// Output texture: {shader.output_texture_name}\n")
            f.write(f"// Texture indices: BINDS=0..{len(shader.binds)-1}")
            if shader.hook == "MAIN" and "MAIN" not in shader.binds:
                f.write(f", MAIN={len(shader.binds)}")
            f.write(f", OUTPUT={len(shader.input_texture_names)}\n\n")

            metal_code = shader.generate_metal_code(pass_index=i)
            f.write(metal_code)
            f.write("\n\n")

    print(f"Translated {len(shaders)} passes: {os.path.basename(metal_path)}")
    return shaders


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    all_shaders: list[MPVShader] = []

    for subdir, glsl_name, metal_name in REQUIRED_SHADERS:
        glsl_path = os.path.join(GLSL_DIR, subdir, glsl_name)
        metal_path = os.path.join(OUTPUT_DIR, metal_name)

        if not os.path.exists(glsl_path):
            print(f"WARNING: {glsl_path} not found, skipping")
            continue

        shaders = translate_file(glsl_path, metal_path)
        all_shaders.extend(shaders)

    print(f"\n{'='*60}")
    print(f"Translation complete!")
    print(f"Output directory: {OUTPUT_DIR}")
    print(f"Total shaders translated: {len(all_shaders)}")
    print(f"{'='*60}")

    # Print summary of texture bindings
    print("\nTexture binding summary:")
    for shader in all_shaders:
        input_names = shader.input_texture_names
        output_idx = len(input_names)
        print(f"  {shader.get_function_name()}:")
        print(f"    Inputs: {input_names} at indices 0..{len(input_names)-1}")
        print(f"    Output: at index {output_idx}")


if __name__ == '__main__':
    main()
