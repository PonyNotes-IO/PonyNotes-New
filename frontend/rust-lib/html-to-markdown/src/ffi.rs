use std::ffi::{CString, CStr};
use std::os::raw::{c_char, c_uchar};
use crate::{convert_html_to_markdown, create_html_viewer_content};
use anyhow::{Result, Context};
use log::{info, error};

/// HTML到Markdown转换的FFI绑定
/// 专门处理HTML文档的智能解析，保留文档结构、标题、链接、表格等格式

/// 处理HTML文件并返回Markdown格式内容
/// 
/// # Arguments
/// * `html_data` - HTML文件的字节数据指针
/// * `html_size` - HTML文件的字节大小
/// * `filename` - 文件名（用于标题提取）
/// * `mode` - 处理模式：0=智能解析, 1=显示源代码, 2=传统解析
/// 
/// # Returns
/// * 包含解析结果的CString指针，如果失败则返回空字符串
#[no_mangle]
pub extern "C" fn html_to_markdown_parse(
    html_data: *const c_uchar,
    html_size: usize,
    filename: *const c_char,
    mode: i32,
) -> *mut c_char {
    let html_content = unsafe {
        std::slice::from_raw_parts(html_data, html_size)
    };
    
    let filename_str = unsafe {
        CStr::from_ptr(filename).to_string_lossy().to_string()
    };
    
    let html_str = match String::from_utf8(html_content.to_vec()) {
        Ok(s) => s,
        Err(e) => {
            error!("HTML内容不是有效的UTF-8: {}", e);
            return CString::new("").unwrap().into_raw();
        }
    };
    
    let result = match mode {
        0 => {
            // 智能解析
            match convert_html_to_markdown(&html_str, &filename_str) {
                Ok(content) => content,
                Err(e) => {
                    error!("智能HTML解析失败: {}", e);
                    return CString::new("HTML解析失败").unwrap().into_raw();
                }
            }
        }
        1 => {
            // 显示HTML源代码
            create_html_viewer_content(&filename_str, &html_str)
        }
        2 => {
            // 传统解析
            let cleaned = html_str
                .replace("<br>", "\n")
                .replace("<br/>", "\n")
                .replace("<br />", "\n");
            
            let re = regex::Regex::new(r"<[^>]*>").unwrap();
            let text = re.replace_all(&cleaned, "");
            
            format!("# {}\n\n{}", filename_str, text.trim())
        }
        _ => {
            error!("未知的处理模式: {}", mode);
            return CString::new("未知的处理模式").unwrap().into_raw();
        }
    };
    
    match CString::new(result) {
        Ok(cstring) => cstring.into_raw(),
        Err(e) => {
            error!("创建CString失败: {}", e);
            CString::new("").unwrap().into_raw()
        }
    }
}

/// 检查HTML解析器是否可用
/// 
/// # Returns
/// * 1表示可用，0表示不可用
#[no_mangle]
pub extern "C" fn html_to_markdown_check_availability() -> i32 {
    1 // 总是可用
}

/// 获取HTML解析器版本信息
/// 
/// # Returns
/// * 版本字符串的CString指针
#[no_mangle]
pub extern "C" fn html_to_markdown_get_version() -> *mut c_char {
    let version = "Rust HTML Parser v1.0.0";
    CString::new(version).unwrap().into_raw()
}

/// 释放CString内存
/// 
/// # Arguments
/// * `ptr` - 要释放的CString指针
#[no_mangle]
pub extern "C" fn html_to_markdown_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

/// 处理HTML字符串并返回Markdown格式内容（字符串版本）
/// 
/// # Arguments
/// * `html_content` - HTML内容字符串
/// * `filename` - 文件名
/// * `mode` - 处理模式：0=智能解析, 1=显示源代码, 2=传统解析
/// 
/// # Returns
/// * 包含解析结果的CString指针
#[no_mangle]
pub extern "C" fn html_to_markdown_parse_string(
    html_content: *const c_char,
    filename: *const c_char,
    mode: i32,
) -> *mut c_char {
    let html_str = unsafe {
        CStr::from_ptr(html_content).to_string_lossy().to_string()
    };
    
    let filename_str = unsafe {
        CStr::from_ptr(filename).to_string_lossy().to_string()
    };
    
    let result = match mode {
        0 => {
            // 智能解析
            match convert_html_to_markdown(&html_str, &filename_str) {
                Ok(content) => content,
                Err(e) => {
                    error!("智能HTML解析失败: {}", e);
                    return CString::new("HTML解析失败").unwrap().into_raw();
                }
            }
        }
        1 => {
            // 显示HTML源代码
            create_html_viewer_content(&filename_str, &html_str)
        }
        2 => {
            // 传统解析
            let cleaned = html_str
                .replace("<br>", "\n")
                .replace("<br/>", "\n")
                .replace("<br />", "\n");
            
            let re = regex::Regex::new(r"<[^>]*>").unwrap();
            let text = re.replace_all(&cleaned, "");
            
            format!("# {}\n\n{}", filename_str, text.trim())
        }
        _ => {
            error!("未知的处理模式: {}", mode);
            return CString::new("未知的处理模式").unwrap().into_raw();
        }
    };
    
    match CString::new(result) {
        Ok(cstring) => cstring.into_raw(),
        Err(e) => {
            error!("创建CString失败: {}", e);
            CString::new("").unwrap().into_raw()
        }
    }
}
