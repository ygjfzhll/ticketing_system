import jwt from "jsonwebtoken";
import fs from "fs";
import path from "path";

const API = "https://open.feishu.cn/open-apis";
let settings = null;

function cfg() {
  return {
    appId: settings?.app_id || process.env.FEISHU_APP_ID || "",
    appSecret: settings?.app_secret || process.env.FEISHU_APP_SECRET || "",
    redirectUri: settings?.redirect_uri || process.env.FEISHU_REDIRECT_URI || "http://localhost:3000/api/auth/feishu/callback",
    enabled: settings ? Number(settings.enabled) !== 0 : true
  };
}

export function feishuEnabled() {
  const c = cfg();
  return Boolean(c.enabled && c.appId && c.appSecret && c.redirectUri);
}

export function publicFeishuSettings() {
  const c = cfg();
  const configured = Boolean(c.appId && c.appSecret && c.redirectUri);
  return { appId: c.appId, redirectUri: c.redirectUri, hasSecret: Boolean(c.appSecret), configured, enabled: feishuEnabled() };
}

export async function ensureFeishuSettings(pool) {
  await pool.query("CREATE TABLE IF NOT EXISTS feishu_settings (id TINYINT PRIMARY KEY, app_id VARCHAR(128) NOT NULL DEFAULT '', app_secret VARCHAR(256) NOT NULL DEFAULT '', redirect_uri VARCHAR(500) NOT NULL DEFAULT '', updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP)");
  await pool.query("ALTER TABLE feishu_settings ADD COLUMN enabled TINYINT(1) NOT NULL DEFAULT 1").catch(error => { if (error.code !== "ER_DUP_FIELDNAME") throw error; });
  const [[row]] = await pool.query("SELECT app_id, app_secret, redirect_uri, enabled FROM feishu_settings WHERE id=1");
  if (!row) {
    await pool.query("INSERT INTO feishu_settings(id, app_id, app_secret, redirect_uri) VALUES(1,?,?,?)", [process.env.FEISHU_APP_ID || "", process.env.FEISHU_APP_SECRET || "", process.env.FEISHU_REDIRECT_URI || "http://localhost:3000/api/auth/feishu/callback"]);
  }
  const [[fresh]] = await pool.query("SELECT app_id, app_secret, redirect_uri, enabled FROM feishu_settings WHERE id=1");
  settings = fresh;
}


function writeEnvFile(updates) {
  const file = path.resolve(".env");
  let text = "";
  try { text = fs.readFileSync(file, "utf8"); } catch { text = ""; }
  if (text && !text.endsWith("\n")) text += "\n";
  for (const [key, value] of Object.entries(updates)) {
    const safe = String(value ?? "").replace(/\r|\n/g, "");
    const line = key + "=" + safe;
    const pattern = new RegExp("^" + key + "=.*$", "m");
    text = pattern.test(text) ? text.replace(pattern, line) : text + line + "\n";
    process.env[key] = safe;
  }
  fs.writeFileSync(file, text);
}

export async function saveFeishuSettings(pool, input) {
  const current = cfg();
  if (input.enabled === false && !String(input.appId || "").trim() && !String(input.appSecret || "").trim()) {
    await pool.query("UPDATE feishu_settings SET enabled=0 WHERE id=1");
    settings = { ...(settings || {}), app_id: current.appId, app_secret: current.appSecret, redirect_uri: current.redirectUri, enabled: 0 };
    return publicFeishuSettings();
  }
  const appId = String(input.appId || "").trim();
  const redirectUri = String(input.redirectUri || "").trim();
  const appSecret = String(input.appSecret || "").trim() || current.appSecret;
  if (!appId || !appSecret || !redirectUri) throw new Error("App ID、App Secret 和回调地址都不能为空");
  const enabled = input.enabled === false ? 0 : 1;
  const [updated] = await pool.query("UPDATE feishu_settings SET app_id=?, app_secret=?, redirect_uri=?, enabled=? WHERE id=1", [appId, appSecret, redirectUri, enabled]);
  if (!updated.affectedRows) {
    await pool.query("INSERT INTO feishu_settings(id, app_id, app_secret, redirect_uri, enabled) VALUES(1,?,?,?,?)", [appId, appSecret, redirectUri, enabled]);
  }
  writeEnvFile({ FEISHU_APP_ID: appId, FEISHU_APP_SECRET: appSecret, FEISHU_REDIRECT_URI: redirectUri });
  settings = { app_id: appId, app_secret: appSecret, redirect_uri: redirectUri, enabled };
  return publicFeishuSettings();
}

export function webOrigin() {
  return process.env.WEB_ORIGIN || "http://127.0.0.1:5173";
}

export function signState() {
  return jwt.sign({ purpose: "feishu" }, process.env.JWT_SECRET, { expiresIn: "10m" });
}

export function verifyState(state) {
  const data = jwt.verify(state, process.env.JWT_SECRET);
  if (data.purpose !== "feishu") throw new Error("登录状态无效");
}

export function authorizeUrl(state) {
  const url = new URL("https://accounts.feishu.cn/open-apis/authen/v1/authorize");
  url.searchParams.set("client_id", cfg().appId);
  url.searchParams.set("redirect_uri", cfg().redirectUri);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("state", state);
  return url.toString();
}

async function requestJson(url, { method = "GET", token, body } = {}) {
  const response = await fetch(url, {
    method,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      ...(token ? { Authorization: "Bearer " + token } : {})
    },
    body: body ? JSON.stringify(body) : undefined
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok || (data.code && data.code !== 0)) {
    throw new Error(data.msg || data.message || "飞书接口调用失败");
  }
  return data;
}

async function appToken() {
  const data = await requestJson(API + "/auth/v3/app_access_token/internal", {
    method: "POST",
    body: { app_id: cfg().appId, app_secret: cfg().appSecret }
  });
  return data.app_access_token;
}

async function tenantToken() {
  const data = await requestJson(API + "/auth/v3/tenant_access_token/internal", {
    method: "POST",
    body: { app_id: cfg().appId, app_secret: cfg().appSecret }
  });
  return data.tenant_access_token;
}

export async function loginByCode(code) {
  const token = await appToken();
  const exchanged = await requestJson(API + "/authen/v1/oidc/access_token", {
    method: "POST",
    token,
    body: { grant_type: "authorization_code", code }
  });
  const access = exchanged.data?.access_token;
  if (!access) throw new Error("没有获取到飞书用户身份");
  const info = await requestJson(API + "/authen/v1/user_info", { token: access });
  return info.data || {};
}

async function paged(url, token) {
  const items = [];
  let pageToken = "";
  for (let i = 0; i < 30; i++) {
    const next = new URL(url);
    if (pageToken) next.searchParams.set("page_token", pageToken);
    const data = await requestJson(next, { token });
    items.push(...(data.data?.items || []));
    if (!data.data?.has_more) break;
    pageToken = data.data.page_token;
    if (!pageToken) break;
  }
  return items;
}

export async function syncDirectory(pool) {
  const token = await tenantToken();
  const departments = await paged(API + "/contact/v3/departments/0/children?department_id_type=open_department_id&fetch_child=true&page_size=50", token);
  let departmentCount = 0;
  for (const department of departments) {
    const openId = department.open_department_id;
    const name = department.name || "未命名部门";
    const [[byFeishu]] = await pool.query("SELECT id FROM departments WHERE feishu_open_id=? LIMIT 1", [openId]);
    if (byFeishu) {
      await pool.query("UPDATE departments SET name=?, is_active=1 WHERE id=?", [name, byFeishu.id]);
    } else {
      const [[byName]] = await pool.query("SELECT id, feishu_open_id FROM departments WHERE name=? LIMIT 1", [name]);
      if (byName && !byName.feishu_open_id) {
        await pool.query("UPDATE departments SET feishu_open_id=?, is_active=1 WHERE id=?", [openId, byName.id]);
      } else if (!byName) {
        try { await pool.query("INSERT INTO departments(name, feishu_open_id) VALUES(?,?)", [name, openId]); }
        catch (error) { if (error.code !== "ER_DUP_ENTRY") throw error; }
      }
    }
    departmentCount++;
  }
  const seen = new Set();
  let created = 0;
  let updated = 0;
  const departmentIds = departments.map(item => item.open_department_id);
  for (const departmentId of departmentIds) {
    const users = await paged(API + "/contact/v3/users/find_by_department?department_id_type=open_department_id&user_id_type=open_id&page_size=50&department_id=" + encodeURIComponent(departmentId), token);
    const department = departments.find(item => item.open_department_id === departmentId);
    for (const user of users) {
      if (!user.open_id || seen.has(user.open_id)) continue;
      seen.add(user.open_id);
      const result = await upsertFeishuUser(pool, {
        ...user,
        department_name: department?.name || null,
        department_id: departmentId,
        is_resigned: Boolean(user.status?.is_resigned)
      });
      if (result.created) created++; else updated++;
    }
  }
  await pool.query("UPDATE users u JOIN users m ON m.feishu_open_id=u.manager_open_id SET u.manager_user_id=m.id WHERE u.manager_open_id IS NOT NULL AND u.manager_open_id<>'' AND (u.manager_user_id IS NULL OR u.manager_user_id<>m.id) AND u.id<>m.id");
  return { departments: departmentCount, created, updated };
}

export async function upsertFeishuUser(pool, person) {
  const openId = person.open_id;
  const name = person.name || "飞书用户";
  const email = person.enterprise_email || person.email || "";
  const avatar = person.avatar_url || person.avatar?.avatar_72 || null;
  const active = person.is_resigned ? 0 : 1;
  const [[found]] = await pool.query("SELECT id, username FROM users WHERE feishu_open_id=? LIMIT 1", [openId]);
  if (found) {
    await pool.query("UPDATE users SET name=?, department_name=COALESCE(?,department_name), department_id=COALESCE(?,department_id), external_id=COALESCE(?,external_id), manager_open_id=COALESCE(?,manager_open_id), source='FEISHU', is_active=?, avatar_url=COALESCE(?,avatar_url) WHERE id=?", [name, person.department_name || null, person.department_id || null, person.user_id || null, person.leader_user_id || null, active, avatar, found.id]);
    return { id: found.id, created: false };
  }
  let username = email.includes("@") ? email.split("@")[0] : null;
  if (username) {
    const [[dup]] = await pool.query("SELECT id FROM users WHERE username=? LIMIT 1", [username]);
    if (dup) username = username + "_" + String(openId).slice(-4);
  }
  const [result] = await pool.query("INSERT INTO users(feishu_open_id,username,name,department_name,department_id,external_id,manager_open_id,source,is_active,avatar_url) VALUES(?,?,?,?,?,?,?, 'FEISHU',?,?)", [openId, username, name, person.department_name || null, person.department_id || null, person.user_id || null, person.leader_user_id || null, active, avatar]);
  return { id: result.insertId, created: true };
}
