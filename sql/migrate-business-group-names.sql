USE ticketing_system;
UPDATE roles SET name='开发支持组', description='负责开发类工单的分析、修复与技术支持' WHERE code='development';
UPDATE roles SET name='运维服务组', description='负责服务器、网络、账号与基础设施运维' WHERE code='operations';
UPDATE roles SET name='测试支持组', description='负责测试验证、质量保障与缺陷复现' WHERE code='testing';
UPDATE roles SET name='产品需求组', description='负责产品需求澄清、评审与业务验收' WHERE code='product';
UPDATE roles SET name='设计支持组', description='负责交互、视觉与设计相关支持' WHERE code='ui';
