import os
import re

def fix_null_safety(content):
    # 1. Replace List(n) or new List(n) with List.filled(n, null) or List.generate
    content = re.sub(r'List<([^>]+)>\s+(\w+)\s*=\s*(?:new\s+)?List(?:<\1>)?\(([^)]+)\);', 
                     r'List<\1?> \2 = List<\1?>.filled(\3, null);', content)
    
    # 2. Fix while((block = reader.readNextBlock(...)) != null)
    content = re.sub(r'StreamReader\s+(\w+);\s*while\s*\(\(\1\s*=\s*([^)]+)\)\s*!=\s*null\)',
                     r'StreamReader? \1; while ((\1 = \2) != null)', content)
    
    # 3. Handle @required -> required
    content = content.replace('@required', 'required')
    
    # 4. Handle List() -> []
    content = re.sub(r'List<([^>]+)>\s+(\w+)\s*=\s*(?:new\s+)?List(?:<\1>)?\(\);', 
                     r'List<\1> \2 = [];', content)

    # 5. Add late to private fields that are not initialized
    # Pattern: Type _fieldName; (not initialized)
    # This is risky, but we'll target private fields in classes.
    def add_late(match):
        line = match.group(0)
        if 'late' in line or '=' in line or 'static' in line or 'final' in line or '?' in line:
            return line
        return '  late ' + line.lstrip()

    content = re.sub(r'^\s+(?!late|final|static|abstract|const|external|factory|covariant)(\w+(?:<[^>]+>)?)\s+(_\w+);', add_late, content, flags=re.MULTILINE)

    return content

def process_directory(directory):
    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.endswith('.dart'):
                path = os.path.join(root, file)
                with open(path, 'r', encoding='utf-8') as f:
                    content = f.read()
                
                new_content = fix_null_safety(content)
                
                if new_content != content:
                    with open(path, 'w', encoding='utf-8') as f:
                        f.write(new_content)
                    print(f"Fixed {path}")

if __name__ == "__main__":
    process_directory('dependencies/Flare-Flutter')
    process_directory('dependencies/Nima-Flutter')
