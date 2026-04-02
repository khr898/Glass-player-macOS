#!/usr/bin/env python3
"""
Translate Anime4K GLSL shaders to Metal following the Anime4KMetal pattern.

Key rules:
1. Texture binding is dynamic - indices assigned based on BINDS array order
2. Output is always at the LAST index (after all inputs)
3. HOOKED and MAIN macros reference the same texture unless HOOK is specified
4. BIND textures are bound at indices 0, 1, 2, ...
5. MAIN is bound after BIND textures (if not already bound)
6. Output is bound at the highest index

This script produces Metal shaders with CONSISTENT texture binding that can be
called from Anime4KMetalPipeline.swift.
"""

import re
import os
import sys

def parse_glsl(glsl_content):
    """Parse GLSL shader and extract metadata and code."""
    shaders = []
    current = None

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
                # New shader description
                if current:
                    shaders.append(current)
                current = {
                    'name': ' '.join(parts[1:]),
                    'hook': None,
                    'binds': [],
                    'save': None,
                    'width': None,
                    'height': None,
                    'when': None,
                    'components': None,
                    'code': []
                }
            elif current:
                if cmd == 'HOOK':
                    current['hook'] = parts[1] if len(parts) > 1 else 'MAIN'
                    if current['hook'] == 'PREKERNEL':
                        current['hook'] = 'MAIN'
                elif cmd == 'BIND':
                    if len(parts) > 1:
                        current['binds'].append(parts[1])
                elif cmd == 'SAVE':
                    if len(parts) > 1:
                        current['save'] = parts[1]
                elif cmd == 'WIDTH':
                    if len(parts) >= 2:
                        current['width'] = parts[1]
                elif cmd == 'HEIGHT':
                    if len(parts) >= 2:
                        current['height'] = parts[1]
                elif cmd == 'WHEN':
                    current['when'] = ' '.join(parts[1:])
                elif cmd == 'COMPONENTS':
                    if len(parts) > 1:
                        current['components'] = int(parts[1])
        elif current:
            current['code'].append(line)

    if current:
        shaders.append(current)

    return shaders


def generate_metal_shader(shader):
    """Generate Metal shader from parsed GLSL."""
    name = shader['name']
    hook = shader.get('hook') or 'MAIN'
    binds = shader.get('binds', [])
    save = shader.get('save')
    code = shader.get('code', [])

    # Function name from shader name
    func_name = re.sub(r'[^a-zA-Z0-9]', '', name)

    # Build header with macros
    header = """#include <metal_stdlib>
using namespace metal;

using vec2 = float2;
using vec3 = float3;
using vec4 = float4;
using ivec2 = int2;
using mat4 = float4x4;

"""

    # Generate BIND macros
    bind_index = 0
    bind_macros = []
    for bind in binds:
        bind_macros.append(f"""#define {bind}_pos mtlPos
#define {bind}_size float2({bind}.get_width(), {bind}.get_height())
#define {bind}_pt (float2(1, 1) / {bind}_size)
#define {bind}_tex(pos) {bind}.sample(textureSampler, pos)
#define {bind}_texOff(off) {bind}_tex({bind}_pos + {bind}_pt * float2(off))

""")
        bind_index += 1

    # Generate HOOKED/MAIN macros
    if hook == 'MAIN':
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

    # Process code - replace function calls with extra args
    functions = []
    processed_code = []
    in_function = False
    current_func_name = None

    for line in code:
        # Detect function definition
        func_match = re.match(r'^(\\w+(?:\\s+\\w+)*?)\\s+(\\w+)\\s*\\((.*)\\)\\s*\\{?\\s*$', line)
        if func_match and not line.startswith('#'):
            ret_type = func_match.group(1)
            func_name_inner = func_match.group(2)
            args = func_match.group(3)

            current_func_name = func_name_inner
            functions.append(func_name_inner)
            in_function = True

            # Build extra args for internal functions
            extra_args = []
            for bind in binds:
                extra_args.append(f"texture2d<float, access::sample> {bind}")
            if hook == 'MAIN' and 'MAIN' not in binds:
                extra_args.append("texture2d<float, access::sample> MAIN")
            extra_args.append("sampler textureSampler")

            extra_args_str = ', '.join(extra_args)
            if args:
                new_line = f"{ret_type} {func_name_inner}({extra_args_str}, {args}) {{"
            else:
                new_line = f"{ret_type} {func_name_inner}({extra_args_str}) {{"

            processed_code.append(new_line)
            continue

        if in_function and line == '}':
            in_function = False
            current_func_name = None

        # Replace function calls with extra arguments
        new_line = line
        for func in functions:
            # Match function calls and add extra args
            pattern = rf'\\b{func}\\s*\\('
            if re.search(pattern, new_line):
                extra_call_args = []
                for bind in binds:
                    extra_call_args.append(bind)
                if hook == 'MAIN' and 'MAIN' not in binds:
                    extra_call_args.append('MAIN')
                extra_call_args.append('textureSampler')

                extra_call_str = ', '.join(extra_call_args)
                new_line = re.sub(pattern, f'{func}({extra_call_str}, ', new_line)
                # Fix double commas or trailing commas
                new_line = re.sub(r', , ', ', ', new_line)
                new_line = re.sub(r', \\)', ')', new_line)

        processed_code.append(new_line)

    # Build hook function signature
    extra_args = []
    extra_call_args = []
    for bind in binds:
        extra_args.append(f"texture2d<float, access::sample> {bind}")
        extra_call_args.append(bind)
    if hook == 'MAIN' and 'MAIN' not in binds:
        extra_args.append("texture2d<float, access::sample> MAIN")
        extra_call_args.append("MAIN")
    extra_args.append("sampler textureSampler")
    extra_call_args.append("textureSampler")

    extra_args_str = ', '.join(extra_args)
    extra_call_args_str = ', '.join(extra_call_args)

    # Build kernel function signature with CORRECT texture binding
    # BINDS go at indices 0, 1, 2, ...
    # MAIN goes at index len(binds) (if not in binds)
    # OUTPUT goes at index len(binds) + (1 if MAIN else 0)
    entry_args = []
    texture_idx = 0

    # Bind BINDS at indices 0, 1, 2, ...
    for bind in binds:
        entry_args.append(f"texture2d<float, access::sample> {bind} [[texture({texture_idx})]]")
        texture_idx += 1

    # MAIN at next index (if HOOK is MAIN and MAIN not in binds)
    main_texture_idx = texture_idx
    if hook == 'MAIN' and 'MAIN' not in binds:
        entry_args.append(f"texture2d<float, access::sample> MAIN [[texture({texture_idx})]]")
        texture_idx += 1

    # OUTPUT at the LAST index
    output_texture_idx = texture_idx
    entry_args.append(f"texture2d<float, access::write> output [[texture({texture_idx})]]")
    texture_idx += 1

    entry_args.append("uint2 gid [[thread_position_in_grid]]")
    entry_args.append("sampler textureSampler [[sampler(0)]]")

    entry_args_str = ', '.join(entry_args)

    # Build kernel
    kernel = f"""
kernel void {func_name}(
    {entry_args_str}) {{
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook({extra_call_args_str}), gid);
}}
"""

    # Combine all parts
    result = header
    result += ''.join(bind_macros)
    result += '\n'.join(processed_code)
    result += kernel

    return result, func_name, binds, main_texture_idx, output_texture_idx


def translate_file(input_path, output_path):
    """Translate a single GLSL file to Metal."""
    with open(input_path, 'r') as f:
        glsl = f.read()

    shaders = parse_glsl(glsl)

    all_kernels = []
    for shader in shaders:
        metal_code, func_name, binds, main_idx, output_idx = generate_metal_shader(shader)
        all_kernels.append((func_name, metal_code, binds, main_idx, output_idx))

    # Write combined output
    with open(output_path, 'w') as f:
        f.write("// Auto-generated from GLSL using translate_anime4k_glsl.py\n")
        f.write("// Texture binding: BINDS=[0..N-1], MAIN=[N], OUTPUT=[N+1]\n\n")
        for func_name, metal_code, binds, main_idx, output_idx in all_kernels:
            f.write(f"// Kernel: {func_name}\n")
            f.write(f"// BINDS: {binds}\n")
            f.write(f"// MAIN texture index: {main_idx}\n")
            f.write(f"// OUTPUT texture index: {output_idx}\n\n")
            f.write(metal_code)
            f.write("\n\n")

    print(f"Translated {len(all_kernels)} kernels to {output_path}")
    return all_kernels


def main():
    if len(sys.argv) < 2:
        print("Usage: translate_anime4k_glsl.py <glsl_file> [output_file]")
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2] if len(sys.argv) > 2 else input_path.replace('.glsl', '.metal')

    translate_file(input_path, output_path)


if __name__ == '__main__':
    main()
