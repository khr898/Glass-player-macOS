#!/usr/bin/env python3
"""
Translate only the required Anime4K GLSL shaders to Metal.
Follows the Anime4KMetal pattern for consistent texture binding.
"""

import re
import os

# Required shaders for Glass Player presets
REQUIRED_SHADERS = [
    ("Restore/Anime4K_Clamp_Highlights.glsl", "Anime4K_Clamp_Highlights.metal"),
    ("Restore/Anime4K_Restore_CNN_S.glsl", "Anime4K_Restore_CNN_S.metal"),
    ("Restore/Anime4K_Restore_CNN_M.glsl", "Anime4K_Restore_CNN_M.metal"),
    ("Restore/Anime4K_Restore_CNN_VL.glsl", "Anime4K_Restore_CNN_VL.metal"),
    ("Restore/Anime4K_Restore_CNN_Soft_S.glsl", "Anime4K_Restore_CNN_Soft_S.metal"),
    ("Restore/Anime4K_Restore_CNN_Soft_M.glsl", "Anime4K_Restore_CNN_Soft_M.metal"),
    ("Restore/Anime4K_Restore_CNN_Soft_VL.glsl", "Anime4K_Restore_CNN_Soft_VL.metal"),
    ("Upscale/Anime4K_Upscale_CNN_x2_S.glsl", "Anime4K_Upscale_CNN_x2_S.metal"),
    ("Upscale/Anime4K_Upscale_CNN_x2_M.glsl", "Anime4K_Upscale_CNN_x2_M.metal"),
    ("Upscale/Anime4K_Upscale_CNN_x2_VL.glsl", "Anime4K_Upscale_CNN_x2_VL.metal"),
    ("Upscale+Denoise/Anime4K_Upscale_Denoise_CNN_x2_M.glsl", "Anime4K_Upscale_Denoise_CNN_x2_M.metal"),
    ("Upscale+Denoise/Anime4K_Upscale_Denoise_CNN_x2_VL.glsl", "Anime4K_Upscale_Denoise_CNN_x2_VL.metal"),
    ("Upscale/Anime4K_AutoDownscalePre_x2.glsl", "Anime4K_AutoDownscalePre_x2.metal"),
    ("Upscale/Anime4K_AutoDownscalePre_x4.glsl", "Anime4K_AutoDownscalePre_x4.metal"),
]

GLSL_DIR = "/Users/user/Glass-player-macOS/Anime4K_GLSL/glsl"
OUTPUT_DIR = "/tmp/metal-shaders"

def parse_glsl(glsl_content):
    """Parse GLSL and extract shader passes."""
    shaders = []
    current = None
    
    for line in glsl_content.split('\n'):
        line = line.strip()
        if not line:
            continue
        
        if line.startswith('//') and not line.startswith('//!'):
            continue
        
        if line.startswith('//!'):
            parts = line[3:].split()
            if not parts:
                continue
            
            cmd = parts[0]
            if cmd == 'DESC':
                if current:
                    shaders.append(current)
                current = {
                    'name': ' '.join(parts[1:]),
                    'hook': None,
                    'binds': [],
                    'save': None,
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
        elif current:
            current['code'].append(line)
    
    if current:
        shaders.append(current)
    
    return shaders


def generate_metal(shader):
    """Generate Metal shader following Anime4KMetal pattern."""
    name = shader['name']
    hook = shader.get('hook') or 'MAIN'
    binds = shader.get('binds', [])
    save = shader.get('save')
    code = shader.get('code', [])
    
    # Function name
    func_name = re.sub(r'[^a-zA-Z0-9]', '', name)
    
    # Header
    header = """#include <metal_stdlib>
using namespace metal;

using vec2 = float2;
using vec3 = float3;
using vec4 = float4;
using ivec2 = int2;
using mat4 = float4x4;

"""
    
    # BIND macros
    bind_macros = []
    for bind in binds:
        bind_macros.append(f"""#define {bind}_pos mtlPos
#define {bind}_size float2({bind}.get_width(), {bind}.get_height())
#define {bind}_pt (float2(1, 1) / {bind}_size)
#define {bind}_tex(pos) {bind}.sample(textureSampler, pos)
#define {bind}_texOff(off) {bind}_tex({bind}_pos + {bind}_pt * float2(off))

""")
    
    # HOOKED/MAIN macros
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
    
    # Process code
    functions = []
    processed_code = []
    in_function = False
    
    for line in code:
        func_match = re.match(r'^(\w+(?:\s+\w+)*?)\s+(\w+)\s*\((.*)\)\s*\{?\s*$', line)
        if func_match and not line.startswith('#'):
            ret_type = func_match.group(1)
            func_name_inner = func_match.group(2)
            args = func_match.group(3)
            
            functions.append(func_name_inner)
            in_function = True
            
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
        
        # Replace function calls
        new_line = line
        for func in functions:
            pattern = rf'\b{func}\s*\('
            if re.search(pattern, new_line):
                extra_call_args = []
                for bind in binds:
                    extra_call_args.append(bind)
                if hook == 'MAIN' and 'MAIN' not in binds:
                    extra_call_args.append('MAIN')
                extra_call_args.append('textureSampler')
                
                extra_call_str = ', '.join(extra_call_args)
                new_line = re.sub(pattern, f'{func}({extra_call_str}, ', new_line)
                new_line = re.sub(r', , ', ', ', new_line)
                new_line = re.sub(r', \)', ')', new_line)
        
        processed_code.append(new_line)
    
    # Build kernel with CORRECT texture binding
    # BINDS at 0, 1, 2, ...
    # MAIN at len(binds) if not in binds
    # OUTPUT at last index
    entry_args = []
    texture_idx = 0
    
    for bind in binds:
        entry_args.append(f"texture2d<float, access::sample> {bind} [[texture({texture_idx})]]")
        texture_idx += 1
    
    main_idx = texture_idx
    if hook == 'MAIN' and 'MAIN' not in binds:
        entry_args.append(f"texture2d<float, access::sample> MAIN [[texture({texture_idx})]]")
        texture_idx += 1
    
    output_idx = texture_idx
    entry_args.append(f"texture2d<float, access::write> output [[texture({texture_idx})]]")
    texture_idx += 1
    
    entry_args.append("uint2 gid [[thread_position_in_grid]]")
    entry_args.append("sampler textureSampler [[sampler(0)]]")
    
    # Build hook call args
    hook_call_args = []
    for bind in binds:
        hook_call_args.append(bind)
    if hook == 'MAIN' and 'MAIN' not in binds:
        hook_call_args.append('MAIN')
    hook_call_args.append('textureSampler')
    
    kernel = f"""
kernel void {func_name}(
    {', '.join(entry_args)}) {{
    float2 mtlPos = float2(gid) / (float2(output.get_width(), output.get_height()) - float2(1, 1));
    output.write(hook({', '.join(hook_call_args)}), gid);
}}
"""
    
    result = header + ''.join(bind_macros) + '\n'.join(processed_code) + kernel
    
    return result, func_name, binds, main_idx if hook == 'MAIN' and 'MAIN' not in binds else -1, output_idx


def translate_file(glsl_path, metal_path):
    """Translate GLSL file to Metal."""
    with open(glsl_path, 'r') as f:
        glsl = f.read()
    
    shaders = parse_glsl(glsl)
    
    with open(metal_path, 'w') as f:
        f.write("// Auto-generated from GLSL using translate_required_shaders.py\n")
        f.write("// Texture binding: BINDS=[0..N-1], MAIN=[N], OUTPUT=[N+1]\n")
        f.write(f"// Source: {os.path.basename(glsl_path)}\n\n")
        
        for shader in shaders:
            metal_code, func_name, binds, main_idx, output_idx = generate_metal(shader)
            f.write(f"// Kernel: {func_name}\n")
            f.write(f"// BINDS: {binds}\n")
            f.write(f"// MAIN texture index: {main_idx}\n")
            f.write(f"// OUTPUT texture index: {output_idx}\n\n")
            f.write(metal_code)
            f.write("\n\n")
    
    print(f"Translated {len(shaders)} passes: {os.path.basename(metal_path)}")


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    for glsl_subpath, metal_name in REQUIRED_SHADERS:
        glsl_path = os.path.join(GLSL_DIR, glsl_subpath)
        metal_path = os.path.join(OUTPUT_DIR, metal_name)
        
        if not os.path.exists(glsl_path):
            print(f"WARNING: {glsl_path} not found, skipping")
            continue
        
        translate_file(glsl_path, metal_path)
    
    print(f"\nTranslation complete. Output: {OUTPUT_DIR}")


if __name__ == '__main__':
    main()
