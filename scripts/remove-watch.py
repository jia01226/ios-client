"""CI 用：本次不打手表时，把 KeWatch 依赖和 target 从 project.yml 里临时摘掉。

只在 runner 的工作副本上改，不提交；打手表的时候不会跑这个脚本。
"""
import pathlib
import re

p = pathlib.Path("project.yml")
s = p.read_text(encoding="utf-8")

# 依赖
s = s.replace("      # 11-25 手表上的柯：跟着 iPhone App 一起装到手表\n      - target: KeWatch\n", "")
s = s.replace("      - target: KeWatch\n", "")

# target 整段（到 KeAppTests 之前）
s = re.sub(r"\n  KeWatch:\n(?:.*\n)*?(?=\n  KeAppTests:)", "\n", s)

p.write_text(s, encoding="utf-8")
print("removed KeWatch from project.yml")
