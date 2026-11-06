import { mkdir, readFile, writeFile, realpath } from 'node:fs/promises';
import path from 'node:path';
import { randomUUID } from 'node:crypto';
import { spawn, execFile } from 'node:child_process';
import {
  createAgentSession, DefaultResourceLoader, ModelRuntime, SessionManager,
  SettingsManager, createMcpExtension, createToolSearchExtension,
} from '@earendil-works/pi-coding-agent';

const textResult = (text, isError = false) => ({ content: [{ type: 'text', text }], isError });
// Keep path interpretation identical to the pinned engine, including @, ~ and macOS variants.
const { resolveToCwd, resolveReadPathAsync } = await import(new URL('./core/tools/path-utils.js', import.meta.resolve('@earendil-works/pi-coding-agent')));
const { McpOAuthCredentialStore } = await import(new URL('./extensions/mcp/oauth.js', import.meta.resolve('@earendil-works/pi-coding-agent')));
const { AuthStorage } = await import(new URL('./core/auth-storage.js', import.meta.resolve('@earendil-works/pi-coding-agent')));
export function safeKey(key) {
  if (typeof key !== 'string' || !/^[a-zA-Z0-9_-]{1,180}$/.test(key)) throw Error('无效的会话标识');
  return key;
}
export async function insideDirectory(root, candidate) {
  const base = await realpath(root);
  let resolved = path.resolve(base, candidate);
  const suffix = [];
  while (true) {
    try { resolved = path.join(await realpath(resolved), ...suffix); break; }
    catch (e) {
      if (e.code !== 'ENOENT') throw e;
      const parent = path.dirname(resolved);
      if (parent === resolved) throw e;
      suffix.unshift(path.basename(resolved));
      resolved = parent;
    }
  }
  const relative = path.relative(base, resolved);
  return relative !== '..' && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative);
}

// One host belongs to one authenticated connection; disconnect always revokes its pending actions.
export class AgentHost {
  constructor({ send, dataRoot, remote = false, allowCommands = false, skillDirectories = [] }) {
    this.send = send;
    this.dataRoot = path.resolve(dataRoot);
    this.remote = remote;
    this.allowCommands = allowCommands;
    this.skillDirectories = skillDirectories;
    this.pending = new Map();
    this.closed = false;
    this.busy = false;
    this.initializing = false;
  }
  request(type, data, signal) {
    if (this.closed || signal?.aborted) return Promise.reject(Error('连接已关闭'));
    const id = randomUUID();
    return new Promise((resolve, reject) => {
      const finish = (value, error) => {
        clearTimeout(timer);
        signal?.removeEventListener('abort', abort);
        this.pending.delete(id);
        error ? reject(error) : resolve(value);
      };
      const abort = () => finish(null, Error('操作已取消'));
      const timer = setTimeout(() => finish(null, Error('等待确认或工具响应超时；请检查结果后再继续')), 120000);
      this.pending.set(id, finish);
      signal?.addEventListener('abort', abort, { once: true });
      this.send({ type, id, ...data });
    });
  }
  async receive(record) {
    if (this.closed) return;
    if (record.type === 'interaction_response' || record.type === 'note_result') {
      this.pending.get(record.id)?.(record.result);
      return;
    }
    try {
      let data;
      switch (record.type) {
        case 'initialize':
          if (this.session || this.initializing) throw Error('执行器已初始化');
          this.initializing = true;
          try { data = await this.initialize(record.config); }
          finally { this.initializing = false; }
          break;
        case 'prompt': {
          this.requireSession();
          if (this.busy) throw Error('任务运行中，请使用补充指令或排队发送');
          if (typeof record.message !== 'string' || !record.message.trim()) throw Error('消息不能为空');
          this.busy = true;
          this.calls = 0;
          this.timer = setTimeout(() => { this.send({ type: 'notice', kind: 'error', message: '任务已达到 15 分钟执行上限，正在停止；已提交的操作请查询确认。' }); void this.stop(); }, 15 * 60 * 1000);
          this.send({ type: 'response', id: record.id, success: true });
          try { await this.session.prompt(record.message, { images: record.images, expandPromptTemplates: true }); }
          catch (e) { this.send({ type: 'notice', kind: 'error', message: this.errorText(e) }); }
          finally {
            this.busy = false;
            clearTimeout(this.timer);
            this.sendState();
            this.send({ type: 'settled' });
          }
          return;
        }
        case 'steer': this.requireSession(); data = await this.session.steer(record.message); break;
        case 'follow_up': this.requireSession(); data = await this.session.followUp(record.message); break;
        case 'abort': await this.stop(); break;
        case 'compact': this.requireIdle(); data = await this.session.compact(); this.sendState(); break;
        case 'get_state': this.requireSession(); data = this.state(); break;
        case 'oauth_callback': {
          const callback = this.oauthCallback;
          if (!callback) throw Error('没有待完成的 MCP 登录');
          const received = new URL(record.url);
          if (received.origin !== callback.url.origin || received.pathname !== callback.url.pathname || received.searchParams.get('state') !== callback.state) throw Error('MCP 登录回调无效');
          const response = await fetch(received, { signal: AbortSignal.timeout(10000) });
          if (!response.ok) throw Error('MCP 登录回调失败');
          this.oauthCallback = undefined;
          break;
        }
        case 'list_sessions': this.requireSession(); data = (await SessionManager.listAll(this.sessionDir)).filter(session => session.cwd === this.cwd); break;
        case 'new_session':
        case 'switch_session': {
          this.requireIdle();
          let manager;
          if (record.type === 'switch_session') {
            const list = await SessionManager.listAll(this.sessionDir);
            const found = list.find(s => s.id === record.sessionId && s.cwd === this.cwd);
            if (!found) throw Error('找不到此工作区的会话');
            manager = SessionManager.open(found.path, this.sessionDir);
          } else { manager = SessionManager.create(this.cwd, this.sessionDir); }
          await this.openSession(manager);
          data = this.state();
          break;
        }
        default: throw Error('不支持的命令');
      }
      this.send({ type: 'response', id: record.id, success: true, data });
    } catch (e) {
      this.send({ type: 'response', id: record.id, success: false, error: this.errorText(e) });
      if (record.type === 'prompt') this.send({ type: 'settled' });
    }
  }
  errorText(e) {
    let message = e instanceof Error ? e.message : String(e);
    for (const secret of [this.config?.apiKey]) if (secret) message = message.split(secret).join('[redacted]');
    return message.slice(0, 3000);
  }
  requireSession() { if (!this.session) throw Error('请先连接执行器'); }
  requireIdle() { this.requireSession(); if (this.busy || this.session.isStreaming) throw Error('请先停止当前任务'); }
  async initialize(config) {
    if (!config || typeof config.apiKey !== 'string' || !config.apiKey || !config.model || !config.baseUrl) throw Error('请配置模型地址、名称和 API Key');
    const endpoint = new URL(config.baseUrl);
    if (!['http:', 'https:'].includes(endpoint.protocol)) throw Error('模型地址必须使用 HTTP 或 HTTPS');
    if (config.noteTools?.some(t => !/^[a-zA-Z0-9_]+$/.test(t.name))) throw Error('无效的笔记工具');
    this.config = config;
    this.sessionDir = path.join(this.dataRoot, safeKey(config.scope));
    this.agentDir = path.join(this.sessionDir, 'config');
    this.cwd = this.remote ? path.join(this.sessionDir, 'files') : (config.directory || path.join(this.sessionDir, 'files'));
    await mkdir(this.cwd, { recursive: true, mode: 0o700 });
    await mkdir(this.agentDir, { recursive: true, mode: 0o700 });
    this.oauthState = config.mcpCredentials;
    this.mcpCredentials = new McpOAuthCredentialStore({
      withLock: fn => {
        const transaction = fn(this.oauthState);
        if (transaction.next !== undefined) { this.oauthState = transaction.next; this.send({ type: 'credentials_changed', value: transaction.next }); }
        return transaction.result;
      },
      withLockAsync: async fn => {
        const transaction = await fn(this.oauthState);
        if (transaction.next !== undefined) { this.oauthState = transaction.next; this.send({ type: 'credentials_changed', value: transaction.next }); }
        return transaction.result;
      },
    });
    this.modelRuntime = await ModelRuntime.create({ credentials: AuthStorage.inMemory(), modelsPath: null, refreshOnCreate: false });
    this.modelRuntime.registerProvider('ponynotes', {
      baseUrl: config.baseUrl.replace(/\/$/, ''), api: 'openai-completions', authHeader: true,
      models: [{ id: config.model, name: config.model, reasoning: false, input: ['text', 'image'], contextWindow: config.contextWindow || 128000, maxTokens: 8192 }],
    });
    await this.modelRuntime.setRuntimeApiKey('ponynotes', config.apiKey);
    let manager;
    try {
      const selected = JSON.parse(await readFile(path.join(this.sessionDir, 'selected.json'), 'utf8'));
      const list = await SessionManager.listAll(this.sessionDir);
      const found = list.find(s => s.id === selected.id);
      if (found?.cwd === this.cwd) manager = SessionManager.open(found.path, this.sessionDir);
    } catch (e) { if (e.code !== 'ENOENT') throw e; }
    await this.openSession(manager || SessionManager.create(this.cwd, this.sessionDir));
    return this.state();
  }
  async openSession(manager) {
    await this.teardownSession('switch');
    const settings = SettingsManager.inMemory({
      compaction: { enabled: true }, retry: { enabled: true, maxRetries: 2 },
      defaultTools: this.config.directory ? ['read', 'ls', 'edit', 'write'] : [],
    });
    const servers = Object.entries(this.config.mcpServers || {}).map(([name, config]) => {
      if (!/^[a-zA-Z0-9_-]+$/.test(name)) throw Error('MCP 服务名称只能包含字母、数字、横线和下划线');
      if (!config.url && !config.command) throw Error(`MCP ${name} 缺少地址或启动命令`);
      if (config.auth) throw Error('MCP 认证请使用独立的 headers 或 OAuth，不得转发模型凭据');
      if (config.type === 'sse') throw Error('请使用 Streamable HTTP MCP 地址');
      // Credentials are literal values supplied by the host, never executable config substitutions.
      for (const value of Object.values({ ...config.headers, ...config.env })) {
        if (typeof value !== 'string' || value.startsWith('!') || value.includes('${')) throw Error('MCP 凭据必须为明确的字符串值');
      }
      return { name, config: { ...config, exposure: 'direct' }, source: 'ponynotes', scope: 'extension' };
    });
    const policy = pi => {
      pi.on('tool_call', async event => {
        if (++this.calls > 100) return { block: true, reason: '本次任务已达到 100 次工具调用上限', terminate: true };
        if (event.toolName.startsWith('notes_') || event.toolName === 'update_plan') return;
        if (['read', 'edit', 'write', 'find', 'grep', 'ls'].includes(event.toolName)) {
          const target = event.toolName === 'read' ? await resolveReadPathAsync(event.input.path || '.', this.cwd) : resolveToCwd(event.input.path || '.', this.cwd);
          if (!this.config.directory || !(await insideDirectory(this.cwd, target))) return { block: true, reason: '目标不在授权目录中' };
          event.input.path = target;
          if (['read', 'find', 'grep', 'ls'].includes(event.toolName)) return;
        }
        const allowed = await this.request('approval', { title: event.toolName, arguments: event.input });
        if (allowed !== true) return { block: true, reason: '用户拒绝执行' };
      });
    };
    const loader = new DefaultResourceLoader({
      cwd: this.cwd, agentDir: this.agentDir, settingsManager: settings,
      noExtensions: true, noContextFiles: true, noThemes: true,
      noSkills: true, noPromptTemplates: true,
      additionalSkillPaths: this.remote ? this.skillDirectories : (this.config.skillDirectories || []),
      extensionFactories: [policy, createToolSearchExtension(), createMcpExtension({
        credentials: this.mcpCredentials,
        logPath: path.join(this.agentDir, 'mcp.log'),
        loadConfig: () => ({ servers, errors: [], autoEnableCodemode: false }),
        openUrl: url => {
          const authorization = new URL(url);
          const redirect = authorization.searchParams.get('redirect_uri');
          if (this.remote && redirect) {
            const callback = new URL(redirect);
            if (callback.protocol !== 'http:' || !['127.0.0.1', 'localhost', '[::1]'].includes(callback.hostname)) throw Error('MCP 登录需要 loopback 回调');
            this.oauthCallback = { url: callback, state: authorization.searchParams.get('state') };
          }
          this.send({ type: 'open_url', url, callback: this.remote ? redirect : undefined });
        },
        updateConfig: () => { throw Error('请在小马笔记的 Agent 设置中修改 MCP 配置'); },
      })],
      appendSystemPrompt: [
        `你是小马笔记的 Agent。当前工作区 ID：${this.config.workspaceId}。只操作用户授权范围，不编造页面和块 ID。工具失败时如实说明。写入超时先查询确认，不重复写入。复杂任务用 update_plan 更新步骤。用中文简洁回答，并给出产物。`,
      ],
    });
    await loader.reload();
    const noteTools = (this.config.noteTools || []).map(spec => ({
      name: `notes_${spec.name}`, label: spec.name, description: spec.description, parameters: spec.inputSchema,
      execute: async (_id, args, signal) => {
        // The Flutter business boundary rechecks identity, permissions, schema and approval.
        const result = await this.request('note_call', { name: spec.name, arguments: args }, signal);
        return result || textResult('笔记工具没有返回结果', true);
      },
    }));
    const plan = {
      name: 'update_plan', label: '任务步骤', description: '记录任务步骤与当前执行状态；完成状态须以实际工具结果为依据。',
      parameters: { type: 'object', properties: { steps: { type: 'array', maxItems: 12, items: { type: 'object', properties: { title: { type: 'string' }, status: { type: 'string', enum: ['pending', 'running', 'completed', 'failed'] } }, required: ['title', 'status'] } } }, required: ['steps'] },
      execute: async (_id, args) => {
        this.session.sessionManager.appendCustomEntry('ponynotes-plan', args);
        this.send({ type: 'plan', steps: args.steps }); return textResult(JSON.stringify(args));
      },
    };
    const commandTools = this.config.allowCommands && (!this.remote || this.allowCommands) ? [{
      name: 'run_command', label: '执行命令', description: process.platform === 'win32' ? '经用户确认后通过 PowerShell 7 执行命令。' : '经用户确认后在执行器中执行 shell 命令。',
      parameters: { type: 'object', properties: { command: { type: 'string', minLength: 1 } }, required: ['command'] },
      execute: async (_id, args, signal, update) => new Promise((resolve, reject) => {
        if (signal.aborted) { reject(Error('命令已取消')); return; }
        const executable = process.platform === 'win32' ? 'pwsh.exe' : '/bin/sh';
        const argv = process.platform === 'win32' ? ['-NoProfile', '-NonInteractive', '-Command', args.command] : ['-c', args.command];
        const child = spawn(executable, argv, { cwd: this.cwd, windowsHide: true, detached: process.platform !== 'win32', env: { PATH: process.env.PATH, SystemRoot: process.env.SystemRoot, TEMP: process.env.TEMP, TMP: process.env.TMP, HOME: this.cwd } });
        let output = '';
        const collect = chunk => { output = (output + chunk.toString()).slice(-32000); update?.(textResult(output)); };
        child.stdout.on('data', collect); child.stderr.on('data', collect);
        const killTree = () => {
          if (!child.pid || child.exitCode !== null) return;
          if (process.platform === 'win32') execFile('taskkill.exe', ['/PID', String(child.pid), '/T', '/F'], { windowsHide: true }, () => {});
          else { try { process.kill(-child.pid, 'SIGTERM'); } catch { child.kill(); } }
        };
        const timeout = setTimeout(killTree, 60000);
        signal.addEventListener('abort', killTree, { once: true });
        const cleanup = () => { clearTimeout(timeout); signal.removeEventListener('abort', killTree); };
        child.on('error', error => { cleanup(); reject(error); });
        child.on('close', (code, signal) => { cleanup(); resolve(textResult(`${output}\n退出状态：${code ?? signal}`, code !== 0)); });
      }),
    }] : [];
    const result = await createAgentSession({
      cwd: this.cwd, agentDir: this.agentDir, modelRuntime: this.modelRuntime,
      model: this.modelRuntime.getModel('ponynotes', this.config.model), thinkingLevel: 'off',
      resourceLoader: loader, settingsManager: settings, sessionManager: manager,
      noTools: 'builtin', excludeTools: ['find', 'grep', 'bash', 'powershell'], customTools: [...noteTools, plan, ...commandTools],
    });
    if (this.closed) { result.session.dispose(); throw Error('连接已关闭'); }
    this.session = result.session;
    this.session.agent.toolExecution = 'sequential';
    // File access is opt-in; a shell is never enabled by an MCP configuration.
    const names = this.session.getActiveToolNames();
    if (this.config.directory) names.push('read', 'ls', 'edit', 'write');
    this.session.setActiveToolsByName([...new Set(names)]);
    this.session.subscribe(event => { if (!this.closed) this.send({ type: 'event', event }); });
    const ui = {
      confirm: (title, message) => this.request('approval', { title, message }),
      select: (title, options) => this.request('select', { title, options }),
      input: (title, placeholder) => this.request('input', { title, message: placeholder }),
      notify: (message, kind) => this.send({ type: 'notice', message, kind }),
      setStatus: (key, message) => this.send({ type: 'notice', message: message || '', key }),
      setWidget: () => {}, setTitle: () => {}, setEditorText: () => {},
      isEditorExpanded: () => false, getEditorText: () => '',
      custom: async () => undefined,
    };
    await this.session.bindExtensions({ mode: 'rpc', uiContext: ui, onError: error => this.send({ type: 'notice', kind: 'error', message: this.errorText(error) }) });
    if (this.closed) { this.session.dispose(); throw Error('连接已关闭'); }
    await writeFile(path.join(this.sessionDir, 'selected.json'), JSON.stringify({ id: this.session.sessionManager.getSessionId() }), { mode: 0o600 });
    this.sendState();
  }
  state() {
    return {
      messages: this.session.messages, stats: this.session.getSessionStats(), context: this.session.getContextUsage(),
      steps: this.session.sessionManager.getEntries().filter(e => e.type === 'custom' && e.customType === 'ponynotes-plan').at(-1)?.data?.steps || [],
      tools: this.session.getActiveToolNames(), model: this.config.model, location: this.remote ? '远端执行器' : '本机',
    };
  }
  sendState() { if (this.session && !this.closed) this.send({ type: 'state', data: this.state() }); }
  async stop() {
    for (const finish of [...this.pending.values()]) finish(null, Error('操作已停止；已提交的写入需查询确认结果'));
    await this.session?.abort();
    clearTimeout(this.timer);
  }
  async close() {
    if (this.closing) return this.closing;
    this.closed = true;
    this.closing = (async () => {
      await this.stop();
      await this.teardownSession('exit');
      this.config = undefined;
    })();
    return this.closing;
  }
  async teardownSession(reason) {
    const session = this.session;
    if (!session) return;
    await session.abort();
    await session.extensionRunner.emit({ type: 'session_shutdown', reason });
    session.dispose();
    if (this.session === session) this.session = undefined;
  }
}
