# FlowDesk 工单系统原型

这是一个可直接打开的前端原型，入口为 `index.html`。

## 建议的正式系统流程

`提交者创建 → 按角色路由 → 对应 Leader 审批 → 指派执行者 → 执行完成 → 提交者验证 → 验证通过关闭 / 验证不通过退回执行者`

### 核心设计

- **领导节点与员工节点分离**：审批人只负责审批和指派，执行人只处理任务，提交者只负责验收。
- **状态机驱动**：后端只允许合法的节点迁移，避免前端直接改状态。
- **角色路由**：运维、测试、开发、产品等角色维护 Leader、成员和备用负责人；提交时按角色自动找到审批人。
- **完整审计**：每次审批、指派、处理、退回、验证都写入不可变操作记录，记录操作者、时间、说明和附件。
- **防止无限退回**：保留验证轮次、退回原因和 SLA；超过阈值自动通知 Leader。

## 正式接入飞书

1. 在飞书开放平台创建企业自建应用，配置 OAuth 回调地址和权限。
2. 前端跳转飞书 OAuth，后端用授权码换取用户身份，建立本地用户与 `open_id` 的映射。
3. 通过飞书通讯录同步部门、用户和直属关系；系统权限以本地角色配置为准。
4. 使用飞书消息卡片通知审批、指派、验证和逾期事项，并让卡片按钮回到后端接口完成动作。

## 推荐后端接口

- `POST /api/auth/feishu/callback`
- `GET /api/tickets?status=...&role=...`
- `POST /api/tickets`
- `POST /api/tickets/:id/approve`
- `POST /api/tickets/:id/assign`
- `POST /api/tickets/:id/complete`
- `POST /api/tickets/:id/verify`
- `POST /api/tickets/:id/reject`
- `GET /api/tickets/:id/events`

数据库使用 MySQL 8.0，建议使用 `utf8mb4` 字符集和 InnoDB 存储引擎。核心表为 `users`、`roles`、`role_members`、`tickets`、`ticket_steps`、`ticket_events`、`attachments`、`notifications`。

### MySQL 表设计建议

- 所有主键使用 `BIGINT UNSIGNED`，由应用生成雪花 ID 或 UUID 转换方案。
- 工单状态、节点类型、优先级使用应用层枚举，并在数据库中保留字符串值，便于后续扩展。
- `tickets` 保存当前状态和当前处理人，`ticket_events` 保存完整流转历史。
- `users.feishu_open_id` 建立唯一索引，避免同一飞书用户重复绑定。
- `ticket_events` 按 `ticket_id`、`created_at` 建立联合索引，支持详情时间线查询。
- 附件文件存储在对象存储中，MySQL 只记录文件地址、名称、大小和上传人。
