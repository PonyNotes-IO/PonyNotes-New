use regex::Regex;
use anyhow::Result;
use log::info;

// FFI模块
pub mod ffi;

/// 专业的HTML到Markdown转换器
pub struct HtmlToMarkdownConverter {
    /// 是否保留原始HTML结构
    preserve_structure: bool,
    /// 是否处理表格
    process_tables: bool,
    /// 是否处理图片
    process_images: bool,
    /// 是否处理链接
    process_links: bool,
}

impl Default for HtmlToMarkdownConverter {
    fn default() -> Self {
        Self {
            preserve_structure: true,
            process_tables: true,
            process_images: true,
            process_links: true,
        }
    }
}

impl HtmlToMarkdownConverter {
    /// 创建新的转换器实例
    pub fn new() -> Self {
        Self::default()
    }

    /// 设置是否保留结构
    pub fn with_structure_preservation(mut self, preserve: bool) -> Self {
        self.preserve_structure = preserve;
        self
    }

    /// 设置是否处理表格
    pub fn with_table_processing(mut self, process: bool) -> Self {
        self.process_tables = process;
        self
    }

    /// 设置是否处理图片
    pub fn with_image_processing(mut self, process: bool) -> Self {
        self.process_images = process;
        self
    }

    /// 设置是否处理链接
    pub fn with_link_processing(mut self, process: bool) -> Self {
        self.process_links = process;
        self
    }

    /// 将HTML转换为Markdown
    pub fn convert(&self, html_content: &str, filename: &str) -> Result<String> {
        info!("🔍 开始Rust HTML解析: {}", filename);
        
        // 提取文档标题
        let title = self.extract_title(html_content, filename);
        
        // 转换文档内容
        let mut result = String::new();
        result.push_str(&format!("# {}\n\n", title));
        
        // 处理HTML内容
        let body_content = self.process_html_content(html_content)?;
        result.push_str(&body_content);
        
        // 清理多余的空行
        let cleaned_result = self.clean_markdown(&result);
        
        info!("✅ Rust HTML解析完成，生成Markdown长度: {}", cleaned_result.len());
        
        Ok(cleaned_result)
    }

    /// 提取文档标题
    fn extract_title(&self, html_content: &str, filename: &str) -> String {
        // 尝试从title标签获取
        if let Some(captures) = Regex::new(r"<title[^>]*>(.*?)</title>").unwrap().captures(html_content) {
            let title_text = self.strip_html_tags(&captures[1]).trim().to_string();
            if !title_text.is_empty() {
                return title_text;
            }
        }
        
        // 尝试从第一个h1标签获取
        if let Some(captures) = Regex::new(r"<h1[^>]*>(.*?)</h1>").unwrap().captures(html_content) {
            let h1_text = self.strip_html_tags(&captures[1]).trim().to_string();
            if !h1_text.is_empty() {
                return h1_text;
            }
        }
        
        // 使用文件名
        filename.to_string()
    }

    /// 处理HTML内容
    fn process_html_content(&self, html_content: &str) -> Result<String> {
        let mut content = html_content.to_string();
        
        // 移除script和style标签
        content = Regex::new(r"<script[^>]*>.*?</script>").unwrap().replace_all(&content, "").to_string();
        content = Regex::new(r"<style[^>]*>.*?</style>").unwrap().replace_all(&content, "").to_string();
        
        // 处理表格
        if self.process_tables {
            content = self.process_tables(&content);
        }
        
        // 处理标题
        content = self.process_headings(&content);
        
        // 处理段落
        content = self.process_paragraphs(&content);
        
        // 处理链接
        if self.process_links {
            content = self.process_links(&content);
        }
        
        // 处理图片
        if self.process_images {
            content = self.process_images(&content);
        }
        
        // 处理列表
        content = self.process_lists(&content);
        
        // 处理引用
        content = self.process_blockquotes(&content);
        
        // 处理代码
        content = self.process_code(&content);
        
        // 处理格式化
        content = self.process_formatting(&content);
        
        // 处理换行
        content = self.process_line_breaks(&content);
        
        // 清理HTML标签
        content = self.strip_html_tags(&content);
        
        Ok(content)
    }

    /// 处理表格
    fn process_tables(&self, content: &str) -> String {
        let table_regex = Regex::new(r"<table[^>]*>(.*?)</table>").unwrap();
        table_regex.replace_all(content, |caps: &regex::Captures| {
            let table_content = &caps[1];
            self.convert_table_to_markdown(table_content)
        }).to_string()
    }

    /// 将表格HTML转换为Markdown
    fn convert_table_to_markdown(&self, table_html: &str) -> String {
        let mut result = String::new();
        result.push('\n');
        
        let tr_regex = Regex::new(r"<tr[^>]*>(.*?)</tr>").unwrap();
        let mut rows = Vec::new();
        
        for tr_match in tr_regex.find_iter(table_html) {
            let tr_content = &tr_match.as_str();
            let mut row = Vec::new();
            
            // 处理th和td
            let th_regex = Regex::new(r"<th[^>]*>(.*?)</th>").unwrap();
            let td_regex = Regex::new(r"<td[^>]*>(.*?)</td>").unwrap();
            
            for th_match in th_regex.find_iter(tr_content) {
                let cell_text = self.strip_html_tags(&th_match.as_str()).trim().to_string();
                row.push(cell_text);
            }
            
            for td_match in td_regex.find_iter(tr_content) {
                let cell_text = self.strip_html_tags(&td_match.as_str()).trim().to_string();
                row.push(cell_text);
            }
            
            if !row.is_empty() {
                rows.push(row);
            }
        }
        
        if !rows.is_empty() {
            // 生成Markdown表格
            for (i, row) in rows.iter().enumerate() {
                result.push('|');
                for cell in row {
                    let escaped_cell = cell.replace('|', "\\|");
                    result.push_str(&format!(" {} |", escaped_cell));
                }
                result.push('\n');
                
                // 添加表头分隔符
                if i == 0 {
                    result.push('|');
                    for _ in row {
                        result.push_str(" --- |");
                    }
                    result.push('\n');
                }
            }
        }
        
        result.push('\n');
        result
    }

    /// 处理标题
    fn process_headings(&self, content: &str) -> String {
        let mut result = content.to_string();
        
        // 处理h1-h6
        for i in 1..=6 {
            let heading_regex = Regex::new(&format!(r"<h{}[^>]*>(.*?)</h{}>", i, i)).unwrap();
            result = heading_regex.replace_all(&result, |caps: &regex::Captures| {
                let heading_text = self.strip_html_tags(&caps[1]).trim().to_string();
                if !heading_text.is_empty() {
                    format!("\n{} {}\n\n", "#".repeat(i), heading_text)
                } else {
                    String::new()
                }
            }).to_string();
        }
        
        result
    }

    /// 处理段落
    fn process_paragraphs(&self, content: &str) -> String {
        let p_regex = Regex::new(r"<p[^>]*>(.*?)</p>").unwrap();
        p_regex.replace_all(content, |caps: &regex::Captures| {
            let paragraph_text = self.strip_html_tags(&caps[1]).trim().to_string();
            if !paragraph_text.is_empty() {
                format!("{}\n\n", paragraph_text)
            } else {
                String::new()
            }
        }).to_string()
    }

    /// 处理链接
    fn process_links(&self, content: &str) -> String {
        let link_regex = Regex::new(r#"<a[^>]*href="([^"]*)"[^>]*>(.*?)</a>"#).unwrap();
        link_regex.replace_all(content, |caps: &regex::Captures| {
            let href = &caps[1];
            let text = self.strip_html_tags(&caps[2]).trim().to_string();
            if !text.is_empty() {
                format!("[{}]({})", text, href)
            } else {
                href.to_string()
            }
        }).to_string()
    }

    /// 处理图片
    fn process_images(&self, content: &str) -> String {
        let img_regex = Regex::new(r#"<img[^>]*src="([^"]*)"[^>]*(?:alt="([^"]*)")?[^>]*>"#).unwrap();
        img_regex.replace_all(content, |caps: &regex::Captures| {
            let src = &caps[1];
            let alt = caps.get(2).map(|m| m.as_str()).unwrap_or("图片");
            format!("![{}]({})\n", alt, src)
        }).to_string()
    }

    /// 处理列表
    fn process_lists(&self, content: &str) -> String {
        let mut result = content.to_string();
        
        // 处理有序列表
        let ol_regex = Regex::new(r"<ol[^>]*>(.*?)</ol>").unwrap();
        result = ol_regex.replace_all(&result, |caps: &regex::Captures| {
            self.convert_list_to_markdown(&caps[1], true)
        }).to_string();
        
        // 处理无序列表
        let ul_regex = Regex::new(r"<ul[^>]*>(.*?)</ul>").unwrap();
        result = ul_regex.replace_all(&result, |caps: &regex::Captures| {
            self.convert_list_to_markdown(&caps[1], false)
        }).to_string();
        
        result
    }

    /// 将列表HTML转换为Markdown
    fn convert_list_to_markdown(&self, list_html: &str, is_ordered: bool) -> String {
        let mut result = String::new();
        result.push('\n');
        
        let li_regex = Regex::new(r"<li[^>]*>(.*?)</li>").unwrap();
        for (i, li_match) in li_regex.find_iter(list_html).enumerate() {
            let li_content = &li_match.as_str();
            let li_text = self.strip_html_tags(li_content).trim().to_string();
            if !li_text.is_empty() {
                let prefix = if is_ordered { 
                    format!("{}. ", i + 1) 
                } else { 
                    "- ".to_string() 
                };
                result.push_str(&format!("{}{}\n", prefix, li_text));
            }
        }
        
        result.push('\n');
        result
    }

    /// 处理引用
    fn process_blockquotes(&self, content: &str) -> String {
        let blockquote_regex = Regex::new(r"<blockquote[^>]*>(.*?)</blockquote>").unwrap();
        blockquote_regex.replace_all(content, |caps: &regex::Captures| {
            let quote_text = self.strip_html_tags(&caps[1]).trim().to_string();
            if !quote_text.is_empty() {
                let lines: Vec<&str> = quote_text.split('\n').collect();
                let mut result = String::new();
                result.push('\n');
                for line in lines {
                    result.push_str(&format!("> {}\n", line.trim()));
                }
                result.push('\n');
                result
            } else {
                String::new()
            }
        }).to_string()
    }

    /// 处理代码
    fn process_code(&self, content: &str) -> String {
        let mut result = content.to_string();
        
        // 处理pre标签
        let pre_regex = Regex::new(r"<pre[^>]*>(.*?)</pre>").unwrap();
        result = pre_regex.replace_all(&result, |caps: &regex::Captures| {
            let code_text = self.strip_html_tags(&caps[1]);
            format!("\n```\n{}\n```\n", code_text)
        }).to_string();
        
        // 处理code标签
        let code_regex = Regex::new(r"<code[^>]*>(.*?)</code>").unwrap();
        result = code_regex.replace_all(&result, |caps: &regex::Captures| {
            let code_text = self.strip_html_tags(&caps[1]);
            format!("`{}`", code_text)
        }).to_string();
        
        result
    }

    /// 处理格式化
    fn process_formatting(&self, content: &str) -> String {
        let mut result = content.to_string();
        
        // 处理粗体
        let strong_regex = Regex::new(r"<strong[^>]*>(.*?)</strong>").unwrap();
        result = strong_regex.replace_all(&result, |caps: &regex::Captures| {
            let text = self.strip_html_tags(&caps[1]).trim().to_string();
            format!("**{}**", text)
        }).to_string();
        
        let b_regex = Regex::new(r"<b[^>]*>(.*?)</b>").unwrap();
        result = b_regex.replace_all(&result, |caps: &regex::Captures| {
            let text = self.strip_html_tags(&caps[1]).trim().to_string();
            format!("**{}**", text)
        }).to_string();
        
        // 处理斜体
        let em_regex = Regex::new(r"<em[^>]*>(.*?)</em>").unwrap();
        result = em_regex.replace_all(&result, |caps: &regex::Captures| {
            let text = self.strip_html_tags(&caps[1]).trim().to_string();
            format!("*{}*", text)
        }).to_string();
        
        let i_regex = Regex::new(r"<i[^>]*>(.*?)</i>").unwrap();
        result = i_regex.replace_all(&result, |caps: &regex::Captures| {
            let text = self.strip_html_tags(&caps[1]).trim().to_string();
            format!("*{}*", text)
        }).to_string();
        
        result
    }

    /// 处理换行
    fn process_line_breaks(&self, content: &str) -> String {
        let mut result = content.to_string();
        
        // 处理br标签
        result = Regex::new(r"<br[^>]*/?>").unwrap().replace_all(&result, "\n").to_string();
        
        // 处理hr标签
        result = Regex::new(r"<hr[^>]*/?>").unwrap().replace_all(&result, "\n---\n").to_string();
        
        result
    }

    /// 移除HTML标签
    fn strip_html_tags(&self, html: &str) -> String {
        let tag_regex = Regex::new(r"<[^>]*>").unwrap();
        tag_regex.replace_all(html, "").to_string()
    }

    /// 清理Markdown内容
    fn clean_markdown(&self, markdown: &str) -> String {
        // 移除多余的空行
        let re = Regex::new(r"\n{3,}").unwrap();
        let cleaned = re.replace_all(markdown, "\n\n");
        
        // 移除行首行尾的空白
        cleaned.lines()
            .map(|line| line.trim())
            .collect::<Vec<_>>()
            .join("\n")
            .trim()
            .to_string()
    }
}

/// 便捷函数：将HTML转换为Markdown
pub fn convert_html_to_markdown(html_content: &str, filename: &str) -> Result<String> {
    let converter = HtmlToMarkdownConverter::new()
        .with_structure_preservation(true)
        .with_table_processing(true)
        .with_image_processing(true)
        .with_link_processing(true);
    
    converter.convert(html_content, filename)
}

/// 便捷函数：创建HTML查看器内容
pub fn create_html_viewer_content(filename: &str, html_content: &str) -> String {
    let mut result = String::new();
    result.push_str(&format!("# {} (HTML源文档)\n\n", filename));
    result.push_str("此文档包含原始HTML内容，建议在浏览器中查看以获得最佳显示效果。\n\n");
    result.push_str("## HTML内容预览\n\n");
    result.push_str("```html\n");
    
    // 限制显示的HTML长度
    let preview_length = if html_content.len() > 5000 { 5000 } else { html_content.len() };
    result.push_str(&html_content[..preview_length]);
    
    if html_content.len() > 5000 {
        result.push_str("\n... (内容已截断，完整内容请查看原始文件)");
    }
    
    result.push_str("\n```\n\n");
    result.push_str("*提示：此文档显示的是HTML源代码。要查看渲染后的效果，请在浏览器中打开原始HTML文件。*");
    
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_convert_simple_html() {
        let html = r#"<h1>Test Title</h1><p>This is a <strong>test</strong> paragraph.</p>"#;
        let result = convert_html_to_markdown(html, "test.html").unwrap();
        assert!(result.contains("# Test Title"));
        assert!(result.contains("**test**"));
    }

    #[test]
    fn test_convert_table() {
        let html = r#"<table><tr><th>Header</th></tr><tr><td>Data</td></tr></table>"#;
        let result = convert_html_to_markdown(html, "test.html").unwrap();
        assert!(result.contains("| Header |"));
        assert!(result.contains("| Data |"));
    }
}