# 测试报告

`RustyClean_测试报告.pdf` 是这份报告的可分发版本,与在线 Artifact 内容一致。

## 更新

新结果同步到仓库后:

```bash
bash report/update.sh
```

三步:按当前 CSV 重绘图表 → 嵌入报告 → 重新渲染 PDF。

**这一步只更新图表和 PDF。** 阶段状态、表格下方的解读、待决事项这些文字是手写在
`rustyclean-status.html` 里的,脚本不会碰——数据变了之后,结论要不要跟着改,是人的判断。

## 文件

| 文件 | 说明 |
|---|---|
| `rustyclean-status.html` | 报告正文。同时是发布为 Artifact 的源文件 |
| `make_charts.py` | 从 `scratch/accuracy_comparison.csv` 等 CSV 生成三张 SVG |
| `embed_charts.py` | 按 `aria-label` 匹配替换报告里的图,而不是按位置 |
| `build_pdf.sh` | 包裹成完整 HTML 文档,加打印样式,用无头 Chrome 渲染 |
| `chart_*.svg` | 生成的图,单独留存以便复用 |

## 几处设计取舍

**为什么要包裹一层 HTML。** `rustyclean-status.html` 是 Artifact 片段,没有
`<!doctype html>`、`<head>`、`<body>`——发布时由平台补上。直接打印会得到一个无样式的片段,
所以 `build_pdf.sh` 先包裹再渲染。

**为什么用 Chrome 而不是 pandoc 或 wkhtmltopdf。** 报告里有内联 SVG、CSS 自定义属性和
Google Fonts 网络字体,只有浏览器引擎能把三者同时处理对。

**为什么打印样式要钉死浅色主题。** PDF 没有"查看者主题"这回事;不钉死的话,渲染机器报告
深色偏好时,深色令牌会生效,产出一份深底的 PDF。

**为什么横向。** 报告主体是宽表格(数据集表 7 列 18 行)。纵向 A4 只有约 794px 可用宽度,
表格会挤成一团。

## PDF 是否纳入版本控制

目前纳入。每次更新约 3 MB,更新频繁时会让仓库变大。若只想按需生成,把
`report/*.pdf` 加进 `.gitignore` 即可——源文件和脚本都在,任何时候都能重建。
