#!/usr/bin/env python3
"""
PNG 图片批量等比例缩放脚本
适用于 macOS 系统

用法:
    python resize_png.py -d /path/to/images -f "medal_*.png" -w 256
    python resize_png.py -d ./images -f "*.png" -w 512
"""

import argparse
import sys
import os
from pathlib import Path
from PIL import Image
import fnmatch


def parse_arguments():
    """解析命令行参数"""
    parser = argparse.ArgumentParser(
        description='批量等比例缩放 PNG 图片',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
示例:
    %(prog)s -d /user/linden/images -f "medal_*.png" -w 256
    %(prog)s -d ./assets -f "*.png" -w 512
        """
    )
    
    parser.add_argument(
        '-d', '--directory',
        required=True,
        help='输入图片所在的目录路径'
    )
    
    parser.add_argument(
        '-f', '--filter',
        required=True,
        help='文件通配符模式 (例如: medal_*.png, *.png, icon_??.png)'
    )
    
    parser.add_argument(
        '-w', '--width',
        type=int,
        required=True,
        help='输出图片的目标宽度 (像素)'
    )
    
    parser.add_argument(
        '-o', '--output-dir',
        help='自定义输出目录 (可选，默认自动创建 output{宽度} 目录)'
    )
    
    parser.add_argument(
        '--quality',
        type=int,
        default=95,
        help='PNG 压缩质量 1-100 (默认: 95)'
    )

    return parser.parse_args()


def validate_args(args):
    """验证参数有效性"""
    # 检查输入目录
    input_path = Path(args.directory).expanduser().resolve()
    if not input_path.exists():
        print(f"❌ 错误: 目录不存在: {input_path}")
        sys.exit(1)
    
    if not input_path.is_dir():
        print(f"❌ 错误: 指定路径不是目录: {input_path}")
        sys.exit(1)
    
    # 检查宽度
    if args.width <= 0:
        print("❌ 错误: 宽度必须大于 0")
        sys.exit(1)
    
    # 检查质量参数
    if not 1 <= args.quality <= 100:
        print("❌ 错误: 质量参数必须在 1-100 之间")
        sys.exit(1)
    
    return input_path


def find_matching_files(directory, pattern):
    """根据通配符查找匹配的文件"""
    all_files = list(directory.iterdir())
    matching_files = []
    
    for file_path in all_files:
        if file_path.is_file() and fnmatch.fnmatch(file_path.name, pattern):
            # 确保是 PNG 文件 (不区分大小写)
            if file_path.suffix.lower() == '.png':
                matching_files.append(file_path)
    
    # 按文件名排序
    matching_files.sort(key=lambda x: x.name)
    return matching_files


def resize_image(input_path, output_path, target_width, quality):
    """
    等比例缩放图片
    保持原始宽高比，根据目标宽度计算高度
    """
    try:
        with Image.open(input_path) as img:
            # 确保是 RGBA 模式 (保留透明度)
            if img.mode in ('RGBA', 'LA', 'P'):
                # 保留透明通道
                if img.mode == 'P':
                    img = img.convert('RGBA')
            else:
                # 非透明图片转为 RGB
                img = img.convert('RGB')
            
            original_width, original_height = img.size
            
            # 计算等比例高度
            ratio = target_width / original_width
            target_height = int(original_height * ratio)
            
            # 使用高质量重采样算法 (LANCZOS)
            resized_img = img.resize(
                (target_width, target_height),
                Image.Resampling.LANCZOS
            )
            
            # 保存图片
            if resized_img.mode == 'RGBA':
                resized_img.save(
                    output_path,
                    'PNG',
                    optimize=True,
                    compress_level=9 - (quality // 11)  # 转换质量到压缩级别
                )
            else:
                resized_img.save(
                    output_path,
                    'PNG',
                    optimize=True,
                    compress_level=9 - (quality // 11)
                )
            
            return {
                'success': True,
                'original_size': (original_width, original_height),
                'new_size': (target_width, target_height),
                'ratio': ratio
            }
            
    except Exception as e:
        return {
            'success': False,
            'error': str(e)
        }


def main():
    """主函数"""
    args = parse_arguments()
    input_dir = validate_args(args)
    
    # 查找匹配的文件
    matching_files = find_matching_files(input_dir, args.filter)
    
    if not matching_files:
        print(f"⚠️  在 {input_dir} 下未找到匹配 '{args.filter}' 的 PNG 文件")
        sys.exit(0)
    
    # 确定输出目录
    if args.output_dir:
        output_dir = Path(args.output_dir).expanduser().resolve()
    else:
        # 默认创建 output{宽度} 目录，例如 output256
        output_dir = input_dir / f"output{args.width}"
    
    # 创建输出目录
    output_dir.mkdir(parents=True, exist_ok=True)
    
    print(f"📁 输入目录: {input_dir}")
    print(f"💾 输出目录: {output_dir}")
    print(f"🔍 匹配模式: {args.filter}")
    print(f"📸 找到 {len(matching_files)} 个文件")
    print(f"📏 目标宽度: {args.width}px")
    print("-" * 50)
    
    # 处理统计
    success_count = 0
    failed_files = []
    
    # 批量处理
    for i, file_path in enumerate(matching_files, 1):
        # 输出文件名与输入文件名相同
        output_path = output_dir / file_path.name
        
        # 显示进度
        print(f"[{i}/{len(matching_files)}] 处理: {file_path.name}", end=" ")
        
        # 执行缩放
        result = resize_image(file_path, output_path, args.width, args.quality)
        
        if result['success']:
            orig_w, orig_h = result['original_size']
            new_w, new_h = result['new_size']
            print(f"✅ {orig_w}x{orig_h} → {new_w}x{new_h}")
            success_count += 1
        else:
            print(f"❌ 失败: {result['error']}")
            failed_files.append((file_path.name, result['error']))
    
    # 输出总结
    print("-" * 50)
    print(f"✨ 处理完成: {success_count}/{len(matching_files)} 成功")
    
    if failed_files:
        print(f"\n⚠️  失败文件 ({len(failed_files)}):")
        for name, error in failed_files:
            print(f"   - {name}: {error}")
    
    # 显示打开命令提示
    if success_count > 0:
        print(f"\n💡 在 Finder 中打开输出目录:")
        print(f"   open '{output_dir}'")


if __name__ == "__main__":
    main()