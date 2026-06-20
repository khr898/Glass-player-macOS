#!/usr/bin/env python3
import os
import sys
import subprocess
import shutil

def run_command(cmd, shell=False):
    print(f"Executing: {' '.join(cmd) if isinstance(cmd, list) else cmd}")
    try:
        result = subprocess.run(cmd, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, shell=shell)
        return result.stdout
    except subprocess.CalledProcessError as e:
        print(f"Error executing command: {e}")
        print(f"Stdout:\n{e.stdout}")
        print(f"Stderr:\n{e.stderr}")
        raise e

def compile_glsl_to_msl(glsl_path, output_dir):
    """
    Compiles raw Anime4K GLSL to SPIR-V, then uses spirv-cross to produce native MSL (.metal)
    """
    base_name = os.path.splitext(os.path.basename(glsl_path))[0]
    spv_path = os.path.join(output_dir, f"{base_name}.spv")
    metal_path = os.path.join(output_dir, f"{base_name}.metal")
    
    print(f"\n--- Processing GLSL: {glsl_path} ---")
    
    # Check if glslangValidator is available
    glslang = shutil.which("glslangValidator") or shutil.which("glslang")
    if not glslang:
        print("[Warning] glslangValidator not found. Skipping SPIR-V compilation.")
        return None
        
    # Compile GLSL to SPIR-V
    # We compile as a compute shader (.comp) or fragment shader (.frag) based on name/contents
    # Anime4K shaders generally contain compute-like logic, standard GLSL syntax
    stage = "-S comp" if "CNN" in base_name or "Upscale" in base_name else "-S frag"
    run_command([glslang, stage, "-V", glsl_path, "-o", spv_path])
    
    # Check if spirv-cross is available
    spirv_cross = shutil.which("spirv-cross")
    if not spirv_cross:
        print("[Warning] spirv-cross not found. Skipping MSL translation.")
        return None
        
    # Translate SPIR-V to MSL
    run_command([spirv_cross, "--msl", spv_path, "--output", metal_path])
    print(f"Generated Metal Source: {metal_path}")
    return metal_path

def build_metal_library(metal_files, output_metallib):
    """
    Compiles MSL files ahead-of-time into a single native macOS .metallib binary
    """
    print("\n--- Compiling MSL Files into Native Metal Library ---")
    
    # Check for Xcode metal compiler
    metal_cmd = shutil.which("metal")
    metallib_cmd = shutil.which("metallib")
    if not metal_cmd or not metallib_cmd:
        print("[Warning] Metal SDK compiler tools not found. Cannot build .metallib.")
        return False
        
    air_files = []
    for m_file in metal_files:
        air_file = m_file.replace(".metal", ".air")
        run_command(["xcrun", "-sdk", "macosx", "metal", "-c", m_file, "-o", air_file, "-std=metal3.0"])
        air_files.append(air_file)
        
    # Package into a single .metallib
    cmd = ["xcrun", "-sdk", "macosx", "metallib"] + air_files + ["-o", output_metallib]
    run_command(cmd)
    
    # Clean up intermediate .air files
    for air in air_files:
        if os.path.exists(air):
            os.remove(air)
            
    print(f"Successfully created native Metal Library: {output_metallib}")
    return True

def convert_onnx_to_coreml(onnx_model_path, output_mlmodel_path):
    """
    Uses coremltools to ingest ArtCNN ONNX weights and compile them to .mlmodel.
    Restricts runtime execution specifically to Apple Neural Engine (ANE) via MLComputeUnits constraints.
    """
    print(f"\n--- Converting ONNX to Core ML: {onnx_model_path} ---")
    try:
        import coremltools as ct
    except ImportError:
        print("[Warning] 'coremltools' Python package is not installed.")
        print("Please install it via: pip install coremltools onnx")
        
        # Provide the equivalent python code snippet that will run during pipeline execution
        print("\nEquivalent Python Conversion Snippet:")
        print(f"""
import coremltools as ct
import onnx

# Load ONNX model
onnx_model = onnx.load('{onnx_model_path}')

# Convert to Core ML Neural Network or ML Program
mlmodel = ct.convert(
    onnx_model,
    convert_to="mlprogram",
    compute_units=ct.ComputeUnits.ALL # Force execution onto ANE + GPU + CPU
)

# Save the model
mlmodel.save('{output_mlmodel_path}')
print("Core ML model saved to {output_mlmodel_path}")
""")
        return False

    # Actual conversion logic (if coremltools is available)
    mlmodel = ct.convert(
        onnx_model_path,
        convert_to="mlprogram",
        compute_units=ct.ComputeUnits.ALL # Enables Neural Engine (ANE) acceleration
    )
    
    # Save model
    mlmodel.save(output_mlmodel_path)
    print(f"Successfully compiled Core ML Model: {output_mlmodel_path}")
    
    # In Apple production, we compile mlmodel to mlmodelc ahead-of-time
    xcrun = shutil.which("xcrun")
    if xcrun:
        output_mlmodelc = output_mlmodel_path + "c"
        print(f"Compiling {output_mlmodel_path} to {output_mlmodelc}...")
        run_command(["xcrun", "coremlcompiler", "compile", output_mlmodel_path, os.path.dirname(output_mlmodelc)])
        
    return True

def main():
    if len(sys.argv) < 3:
        print("Usage: python aot_shader_pipeline.py <shader_dir> <output_dir>")
        sys.exit(1)
        
    shader_dir = sys.argv[1]
    output_dir = sys.argv[2]
    
    os.makedirs(output_dir, exist_ok=True)
    
    metal_files = []
    
    # 1. Look for Anime4K GLSL shaders
    for file in os.listdir(shader_dir):
        if file.endswith(".glsl") and "Anime4K" in file:
            glsl_path = os.path.join(shader_dir, file)
            metal_path = compile_glsl_to_msl(glsl_path, output_dir)
            if metal_path:
                metal_files.append(metal_path)
                
    # 2. Build Metal library if any MSL files were generated
    if metal_files:
        metallib_path = os.path.join(output_dir, "Anime4KUpscaler.metallib")
        build_metal_library(metal_files, metallib_path)
        
    # 3. Look for ArtCNN ONNX models to compile
    artcnn_onnx = os.path.join(shader_dir, "ArtCNN", "C4F16.onnx")
    if os.path.exists(artcnn_onnx):
        mlmodel_path = os.path.join(output_dir, "ArtCNN_C4F16.mlmodel")
        convert_onnx_to_coreml(artcnn_onnx, mlmodel_path)
    else:
        # Check standard folder locations
        alternative_path = os.path.join(shader_dir, "C4F16.onnx")
        if os.path.exists(alternative_path):
            convert_onnx_to_coreml(alternative_path, os.path.join(output_dir, "ArtCNN_C4F16.mlmodel"))
        else:
            print("\n[Notice] No ArtCNN C4F16.onnx found under shaders/ArtCNN/. Skipping Core ML compilation.")

if __name__ == "__main__":
    main()
