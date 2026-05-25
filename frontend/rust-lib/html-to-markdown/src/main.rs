use html_to_markdown::{convert_html_to_markdown, create_html_viewer_content};
use anyhow::{Result, Context};
use env_logger;
use log::info;
use std::env;
use std::fs;
use std::path::Path;

fn main() -> Result<()> {
    // 初始化日志
    env_logger::init();
    
    let args: Vec<String> = env::args().collect();
    
    if args.len() < 2 {
        eprintln!("用法: html-to-markdown <HTML文件路径> [模式]");
        eprintln!("模式:");
        eprintln!("  smart    - 智能解析（默认）");
        eprintln!("  source   - 显示HTML源代码");
        eprintln!("  legacy   - 传统解析");
        std::process::exit(1);
    }
    
    let input_path = &args[1];
    let mode = args.get(2).map(|s| s.as_str()).unwrap_or("smart");
    
    // 检查文件是否存在
    if !Path::new(input_path).exists() {
        eprintln!("错误：文件不存在: {}", input_path);
        std::process::exit(1);
    }
    
    // 读取HTML文件
    let html_content = fs::read_to_string(input_path)
        .context("无法读取HTML文件")?;
    
    let filename = Path::new(input_path)
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("unknown");
    
    info!("📄 开始处理HTML文件: {} (模式: {})", filename, mode);
    
    // 根据模式处理HTML
    let markdown_content = match mode {
        "smart" => {
            convert_html_to_markdown(&html_content, filename)
                .context("智能HTML解析失败")?
        }
        "source" => {
            create_html_viewer_content(filename, &html_content)
        }
        "legacy" => {
            // 简单的传统解析：移除HTML标签
            let cleaned = html_content
                .replace("<br>", "\n")
                .replace("<br/>", "\n")
                .replace("<br />", "\n");
            
            let re = regex::Regex::new(r"<[^>]*>").unwrap();
            let text = re.replace_all(&cleaned, "");
            
            format!("# {}\n\n{}", filename, text.trim())
        }
        _ => {
            eprintln!("错误：未知模式: {}", mode);
            std::process::exit(1);
        }
    };
    
    // 输出结果
    println!("{}", markdown_content);
    
    info!("✅ HTML处理完成，输出长度: {}", markdown_content.len());
    
    Ok(())
}

