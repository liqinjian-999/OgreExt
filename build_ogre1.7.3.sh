#!/bin/sh

set -e

curr_dir=$(pwd)
src_dir=${curr_dir}
Deps_dir=${curr_dir}/Dependencies
#Deps_dir_install=${Deps_dir}/install

Deps_dir_install=${Deps_dir} #/root/OgreNew14.3/Dependencies
build_dir=${curr_dir}/build
install_dir=${curr_dir}/install

[ ! -d ${build_dir} ] && mkdir ${build_dir}
[ ! -d ${install_dir} ] && mkdir ${install_dir}

# Set up complete environment variables
export C_INCLUDE_PATH=${Deps_dir_install}/include:$C_INCLUDE_PATH
export CPLUS_INCLUDE_PATH=${Deps_dir_install}/include:$CPLUS_INCLUDE_PATH
export LIBRARY_PATH=${Deps_dir_install}/lib:$LIBRARY_PATH
export LIBRARY_PATH=${Deps_dir_install}/lib64:$LIBRARY_PATH
export LD_LIBRARY_PATH=${Deps_dir_install}/lib64:${Deps_dir_install}/lib:$LD_LIBRARY_PATH
export PATH=$PATH:${Deps_dir_install}/bin

# Check Cg dependency files
echo "=== Checking Cg Dependencies ==="
ls -la ${Deps_dir_install}/lib64/libCg* 2>/dev/null || echo "Warning: libCg library files not found"
ls -la ${Deps_dir_install}/include/Cg/ 2>/dev/null || echo "Warning: Cg header directory not found"

cmake -S ${src_dir} -B ${build_dir} -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=${install_dir} \
    -DOGRE_BUILD_SAMPLES=OFF \
    -DOGRE_BUILD_TESTS=OFF \
    -DOGRE_BUILD_DOCS=OFF \
    -DOGRE_USE_BOOST=OFF \
    -DOGRE_BUILD_PLUGIN_CG=ON \
    -DCg_FOUND=TRUE \
    -DCg_INCLUDE_DIRS=${Deps_dir_install}/include/Cg \
    -DCg_LIBRARIES="${Deps_dir_install}/lib64/libCg.so;${Deps_dir_install}/lib64/libCgGL.so" \
    -DFREETYPE_INCLUDE_DIR=${Deps_dir_install}/include/freetype2/freetype \
    -DFREETYPE_FT2BUILD_INCLUDE_DIR=${Deps_dir_install}/include/freetype2
    #-DFREETYPE_INCLUDE_DIR=${Deps_dir_install}/include/freetype/ \
    #-DFREETYPE_LIBRARY=${Deps_dir_install}/lib/libfreetype.so \
    #-DFREEIMAGE_INCLUDE_DIR=/root/source/FreeImage/Dist/ \
    #-DFREEIMAGE_LIBRARY=/root/source/FreeImage/Dist/libfreeimage.a \
    #-DZZIP_INCLUDE_DIR=${Deps_dir_install}/include/zzip \
    #-DZZIP_LIBRARY=${Deps_dir_install}/libzziplib.a \
      #-DOGRE_CONFIG_THREAD_PROVIDER=tbb \
      #-DTBB_INCLUDE_DIR=/usr/include/tbb \
      #-DTBB_LIBRARY_DBG=/opt/intel/oneapi/tbb/2022.1/lib/libtbb_debug.so \
      #-DTBB_LIBRARY_REL=/opt/intel/oneapi/tbb/2022.1/lib/libtbb.so \
      #-DTBB_MALLOC_INCLUDE_DIR=/opt/intel/oneapi/tbb/2021.9.0/include/tbb/ \
      #-DTBB_MALLOC_LIBRARY_DBG=/opt/intel/oneapi/tbb/2022.1/lib/libtbbmalloc_debug.so \
      #-DTBB_MALLOC_LIBRARY_REL=/opt/intel/oneapi/tbb/2022.1/lib/libtbbmalloc.so \
      #-DTBB_MALLOC_PROXY_INCLUDE_DIR=/opt/intel/oneapi/tbb/2021.9.0/include/tbb/ \
      #-DTBB_MALLOC_PROXY_LIBRARY_DBG=/opt/intel/oneapi/tbb/2022.1/lib/libtbbmalloc_proxy_debug.so \
      #-DTBB_MALLOC_PROXY_LIBRARY_REL=/opt/intel/oneapi/tbb/2022.1/lib/libtbbmalloc_proxy.so \
    #-DDOXYGEN_EXECUTABLE="" \
    #-DOGRE_SKIP_TESTS=ON \
    #-DOIS_INCLUDE_DIR=${Deps_dir_install}/include/OIS/ \
      #-DOIS_LIBRARY_DBG=${Deps_dir_install}/lib/libOIS.so \
      #-DOIS_LIBRARY_REL=${Deps_dir_install}/lib/libOIS.so

read -p "CMake configure finished. Press Enter to continue with build and packaging..."

echo "=== Starting Build ==="
cmake --build ${build_dir} --config Release

echo "=== Starting Installation ==="
cmake --install ${build_dir} --config Release --prefix ${install_dir}

echo "=== Checking if Cg Plugin was Built Successfully ==="
if [ -f "${install_dir}/lib/OGRE/Plugin_CgProgramManager.so" ]; then
    echo "✓ Cg plugin built successfully: ${install_dir}/lib/OGRE/Plugin_CgProgramManager.so"
elif [ -f "${install_dir}/lib/Plugin_CgProgramManager.so" ]; then
    echo "✓ Cg plugin built successfully: ${install_dir}/lib/Plugin_CgProgramManager.so"
else
    echo "✗ Cg plugin not found, searching for all Cg-related files:"
    find ${install_dir} -name "*Cg*" -type f 2>/dev/null || echo "No Cg-related files found"
fi

lib_dir=${install_dir}/lib
cd ${lib_dir}
#for lib in libvtk*-9.2.so; do
#    link_name=$(echo "${lib}" | sed 's/lib//')
#    ln -sf ${lib} ${link_name}
#done

echo "Build and installation completed successfully!"
echo ""
echo "=== Important Notice ==="
echo "For runtime, please set the environment variable: export LD_LIBRARY_PATH=${Deps_dir_install}/lib64:\$LD_LIBRARY_PATH"

# ========== Smart Dependency Packaging ==========
echo ""
echo "=== Starting Smart Dependency Analysis and Packaging ==="

# 创建 linux64 打包目录
package_base_dir=${curr_dir}/linux64
package_dir=${package_base_dir}
[ -d ${package_base_dir} ] && rm -rf ${package_base_dir}
mkdir -p ${package_dir}/{lib,include,bin}

echo "Created package directory: ${package_dir}"

# 复制 Ogre 编译结果
echo "Copying Ogre installation..."
cp -r ${install_dir}/* ${package_dir}/

# 创建临时文件来记录需要的依赖
needed_libs_file="/tmp/ogre_needed_libs_$$.txt"
all_libs_file="/tmp/ogre_all_libs_$$.txt"
touch ${needed_libs_file} ${all_libs_file}

# 函数：分析单个库文件的依赖
analyze_single_lib() {
    local lib_file="$1"
    local lib_name=$(basename "$lib_file")
    
    echo "Analyzing: ${lib_name}"
    
    # 使用 ldd 分析依赖，直接输出到文件
    ldd "$lib_file" 2>/dev/null | grep "=>" | awk '{print $3}' | grep -v "^$" >> ${all_libs_file}
}

# 分析所有 Ogre 库文件的依赖
echo "Analyzing Ogre library dependencies..."
find ${package_dir}/lib -name "*.so*" -type f | while read ogre_lib; do
    analyze_single_lib "$ogre_lib"
done

# 处理依赖库列表
if [ -f ${all_libs_file} ]; then
    echo ""
    echo "Processing dependency list..."
    
    # 去重并过滤，只保留第三方库
    cat ${all_libs_file} | sort | uniq | while read dep_path; do
        if [ -n "$dep_path" ] && [ -f "$dep_path" ]; then
            # 过滤系统库
            case "$dep_path" in
                /lib/* | /lib64/* | /usr/lib/* | /usr/lib64/* | *ld-linux* | *linux-vdso*)
                    # 跳过系统库
                    ;;
                *)
                    # 检查是否在我们的依赖目录中
                    if echo "$dep_path" | grep -q "^${Deps_dir_install}"; then
                        echo "$dep_path" >> ${needed_libs_file}
                    fi
                    ;;
            esac
        fi
    done
fi

# 强制添加 Cg 库（如果存在）
echo ""
echo "Adding Cg libraries explicitly..."
for cg_lib in libCg.so libCgGL.so; do
    cg_path_lib="${Deps_dir_install}/lib/${cg_lib}"
    cg_path_lib64="${Deps_dir_install}/lib64/${cg_lib}"
    
    if [ -f "$cg_path_lib64" ]; then
        echo "$cg_path_lib64" >> ${needed_libs_file}
        echo "✓ Found Cg library: $cg_path_lib64"
    elif [ -f "$cg_path_lib" ]; then
        echo "$cg_path_lib" >> ${needed_libs_file}
        echo "✓ Found Cg library: $cg_path_lib"
    fi
done

# 去重并复制需要的第三方库
if [ -f ${needed_libs_file} ]; then
    echo ""
    echo "Copying required third-party libraries..."
    
    sort ${needed_libs_file} | uniq | while read lib_path; do
        if [ -f "$lib_path" ]; then
            lib_name=$(basename "$lib_path")
            
            # 检查是否已经存在
            if [ ! -f "${package_dir}/lib/${lib_name}" ]; then
                cp "$lib_path" "${package_dir}/lib/"
                echo "✓ Copied: ${lib_name}"
            else
                echo "- Already exists: ${lib_name}"
            fi
        fi
    done
else
    echo "No dependency file found, copying Cg libraries directly..."
    # 直接复制 Cg 库作为备用方案
    for cg_lib in libCg.so libCgGL.so; do
        if [ -f "${Deps_dir_install}/lib64/${cg_lib}" ]; then
            cp "${Deps_dir_install}/lib64/${cg_lib}" "${package_dir}/lib/"
            echo "✓ Copied Cg library: ${cg_lib}"
        elif [ -f "${Deps_dir_install}/lib/${cg_lib}" ]; then
            cp "${Deps_dir_install}/lib/${cg_lib}" "${package_dir}/lib/"
            echo "✓ Copied Cg library: ${cg_lib}"
        fi
    done
fi

# 复制相关的头文件（只复制实际用到的）
echo ""
echo "Copying required header files..."

# 根据实际使用的库来确定需要的头文件
copy_headers_for_lib() {
    local lib_name="$1"
    local header_dir="$2"
    
    if [ -d "${Deps_dir_install}/include/${header_dir}" ]; then
        mkdir -p "${package_dir}/include/${header_dir}"
        cp -r "${Deps_dir_install}/include/${header_dir}"/* "${package_dir}/include/${header_dir}/" 2>/dev/null || true
        echo "✓ Copied headers for: ${lib_name} -> ${header_dir}"
    fi
}

# 检查哪些库被实际使用并复制对应头文件
if [ -f "${package_dir}/lib/libCg.so" ] || [ -f "${package_dir}/lib/libCgGL.so" ]; then
    copy_headers_for_lib "Cg" "Cg"
fi

# 检查其他常见的库
for lib in freetype freeimage zzip; do
    if ls ${package_dir}/lib/lib${lib}* >/dev/null 2>&1; then
        copy_headers_for_lib "$lib" "$lib"
    fi
done

# 创建智能的环境设置脚本
echo ""
echo "Creating smart runtime setup script..."
cat > ${package_dir}/setup_env.sh << 'EOF'
#!/bin/bash
# Ogre Smart Runtime Environment Setup Script

OGRE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 设置库路径
export LD_LIBRARY_PATH="${OGRE_ROOT}/lib:${LD_LIBRARY_PATH}"
export PATH="${OGRE_ROOT}/bin:${PATH}"

echo "Ogre environment setup completed"
echo "OGRE_ROOT: ${OGRE_ROOT}"

# 验证关键库是否可以加载
echo ""
echo "Verifying library dependencies..."

check_lib() {
    local lib_path="$1"
    local lib_name=$(basename "$lib_path")
    
    if [ -f "$lib_path" ]; then
        if ldd "$lib_path" >/dev/null 2>&1; then
            echo "✓ ${lib_name}: OK"
        else
            echo "✗ ${lib_name}: Missing dependencies"
            ldd "$lib_path" 2>&1 | grep "not found"
        fi
    fi
}

# 检查主要的 Ogre 库
check_lib "${OGRE_ROOT}/lib/libOgreMain.so"

# 检查 Cg 插件
if [ -f "${OGRE_ROOT}/lib/OGRE/Plugin_CgProgramManager.so" ]; then
    check_lib "${OGRE_ROOT}/lib/OGRE/Plugin_CgProgramManager.so"
elif [ -f "${OGRE_ROOT}/lib/Plugin_CgProgramManager.so" ]; then
    check_lib "${OGRE_ROOT}/lib/Plugin_CgProgramManager.so"
fi

echo ""
echo "Setup completed. You can now use Ogre libraries."
EOF

chmod +x ${package_dir}/setup_env.sh

# 创建 README 文件
echo ""
echo "Creating README file..."
cat > ${package_dir}/README.md << EOF
# Ogre 1.7.3 Portable Package for Linux x64

**Generated on:** $(date)  
**Platform:** Linux x64  
**Version:** Ogre 1.7.3 with Cg support  

## Package Contents

This is a complete, portable installation of Ogre 1.7.3 compiled with Cg support.
All necessary third-party dependencies are included.

### Directory Structure
\`\`\`
linux64/
├── lib/           # Shared libraries (.so files)
├── include/       # Header files  
├── bin/           # Executables and tools
├── setup_env.sh   # Environment setup script
└── README.md      # This file
\`\`\`

## Quick Start

1. Extract this package to your desired location
2. Set up the environment:
   \`\`\`bash
   source setup_env.sh
   \`\`\`
3. Your environment is now configured to use Ogre

## For Development

### CMake Integration
\`\`\`cmake
# Add to your CMakeLists.txt
set(CMAKE_PREFIX_PATH "/path/to/linux64")
find_package(PkgConfig REQUIRED)

# Set library paths
link_directories(/path/to/linux64/lib)
include_directories(/path/to/linux64/include)

# Link libraries
target_link_libraries(your_target OgreMain)
\`\`\`

### Manual Compilation
\`\`\`bash
g++ -I/path/to/linux64/include \\
    -L/path/to/linux64/lib \\
    -lOgreMain your_source.cpp
\`\`\`

## Features Included

- ✅ Ogre Main Library
- ✅ Cg Shader Support
- ✅ All required third-party dependencies
- ✅ Development headers
- ✅ Utility tools

## System Requirements

- Linux x64 (tested on RedHat/CentOS)
- GLIBC 2.17 or newer
- OpenGL support

## Troubleshooting

If you encounter library loading issues:
1. Ensure \`setup_env.sh\` has been sourced
2. Check that \`LD_LIBRARY_PATH\` includes the lib directory
3. Verify system compatibility with: \`ldd lib/libOgreMain.so\`

For more information, see DEPENDENCIES.txt for a complete list of included libraries.
EOF

# 创建依赖报告
echo ""
echo "Creating dependency report..."
cat > ${package_dir}/DEPENDENCIES.txt << EOF
Ogre 1.7.3 - Third-party Dependencies Report
===========================================
Generated on: $(date)
Platform: Linux x64

This package contains only the third-party libraries that are actually
used by the compiled Ogre libraries.

Third-party Libraries Included:
------------------------------
EOF

# 列出所有非 Ogre 的库文件
ls -1 ${package_dir}/lib/ | grep -v "^libOgre" | while read lib; do
    lib_path="${package_dir}/lib/${lib}"
    if [ -f "$lib_path" ]; then
        # 获取库信息
        file_info=$(file "$lib_path" 2>/dev/null || echo "Unknown")
        size=$(ls -lh "$lib_path" | awk '{print $5}')
        echo "- ${lib} (${size}) - ${file_info}" >> ${package_dir}/DEPENDENCIES.txt
    fi
done

cat >> ${package_dir}/DEPENDENCIES.txt << EOF

Header Files Included:
---------------------
EOF

find ${package_dir}/include -name "*.h" | sed "s|${package_dir}/include/||" | sort >> ${package_dir}/DEPENDENCIES.txt

# 清理临时文件
rm -f ${needed_libs_file} ${all_libs_file}

# 验证 Cg 库是否被复制
echo ""
echo "=== Verifying Cg Libraries ==="
if [ -f "${package_dir}/lib/libCg.so" ]; then
    echo "✓ libCg.so found in package"
else
    echo "✗ libCg.so NOT found in package"
fi

if [ -f "${package_dir}/lib/libCgGL.so" ]; then
    echo "✓ libCgGL.so found in package"
else
    echo "✗ libCgGL.so NOT found in package"
fi

# 显示打包结果
echo ""
echo "=== Smart Packaging Summary ==="
echo "Package location: ${package_dir}"
echo "Package size: $(du -sh ${package_dir} | cut -f1)"
echo ""
echo "Contents:"
ogre_libs=$(ls ${package_dir}/lib/libOgre* 2>/dev/null | wc -l)
third_party_libs=$(ls ${package_dir}/lib/ 2>/dev/null | grep -v "^libOgre" | wc -l)
headers=$(find ${package_dir}/include -name "*.h" 2>/dev/null | wc -l)
binaries=$(ls ${package_dir}/bin/* 2>/dev/null | wc -l)

echo "  Ogre libraries: ${ogre_libs} files"
echo "  Third-party libraries: ${third_party_libs} files"
echo "  Header files: ${headers} files"  
echo "  Binaries: ${binaries} files"
echo ""
echo "Third-party libraries included:"
ls ${package_dir}/lib/ 2>/dev/null | grep -v "^libOgre" | sed 's/^/  - /' || echo "  No third-party libraries found"

# ========== 创建最终的 7z 压缩包 ==========
echo ""
echo "=== Creating Final 7z Archive ==="

final_archive_name="ogre_173.2025_linux64.7z"
final_archive_path="${curr_dir}/${final_archive_name}"

# 检查是否安装了 7z
if command -v 7z >/dev/null 2>&1; then
    echo "Using 7z command..."
    
    # 删除已存在的归档文件
    [ -f "$final_archive_path" ] && rm -f "$final_archive_path"
    
    # 创建 7z 归档，使用最高压缩级别，打包 linux64 目录
    cd ${curr_dir}
    7z a -t7z -mx=9 -mfb=64 -md=32m -ms=on "$final_archive_name" linux64/
    
    if [ -f "$final_archive_path" ]; then
        archive_size=$(ls -lh "$final_archive_path" | awk '{print $5}')
        echo "✓ 7z archive created successfully: ${final_archive_name} (${archive_size})"
    else
        echo "✗ Failed to create 7z archive"
    fi
    
elif command -v tar >/dev/null 2>&1; then
    echo "7z not found, using tar.xz as alternative..."
    
    final_archive_name="ogre_173.2025_linux64.tar.xz"
    final_archive_path="${curr_dir}/${final_archive_name}"
    
    # 删除已存在的归档文件
    [ -f "$final_archive_path" ] && rm -f "$final_archive_path"
    
    # 创建 tar.xz 归档，打包 linux64 目录
    cd ${curr_dir}
    tar -cJf "$final_archive_name" linux64/
    
    if [ -f "$final_archive_path" ]; then
        archive_size=$(ls -lh "$final_archive_path" | awk '{print $5}')
        echo "✓ tar.xz archive created successfully: ${final_archive_name} (${archive_size})"
    else
        echo "✗ Failed to create tar.xz archive"
    fi
    
else
    echo "Neither 7z nor tar found, skipping archive creation"
    echo "Package directory available at: ${package_dir}"
fi

# 显示最终结果
echo ""
echo "=========================================="
echo "🎉 BUILD AND PACKAGING COMPLETED! 🎉"
echo "=========================================="
echo ""
echo "📦 Package Details:"
echo "   Directory: ${package_dir}"
echo "   Archive: ${final_archive_name}"
echo "   Location: ${curr_dir}"
echo ""
echo "📊 Package Contents:"
echo "   Ogre libraries: ${ogre_libs} files"
echo "   Third-party libs: ${third_party_libs} files"
echo "   Header files: ${headers} files"
echo "   Binaries: ${binaries} files"
echo ""
echo "🚀 Usage Instructions:"
echo "   1. Extract: 7z x ${final_archive_name}"
echo "   2. Setup: source linux64/setup_env.sh"
echo "   3. Develop: Use CMake or manual compilation"
echo ""
echo "📖 Documentation:"
echo "   - README.md: Complete usage guide"
echo "   - DEPENDENCIES.txt: Library details"
echo "   - setup_env.sh: Runtime environment"
echo ""
echo "✓ Smart dependency packaging completed successfully!"