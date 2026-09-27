-- ============================================================
--  迁移脚本 01：负荷预测结果表
-- ============================================================
--  为什么不在 load_record 里加一列 "是否预测值"？
--     因为两者性质完全不同：
--       load_record   是"已经发生的事实"，只增不改
--       load_forecast 是"对未来的推测"，会反复重算、可以整批删掉重写
--     混在一张表里，一旦要清理预测结果，就得在事实数据里做条件删除 —— 很危险。
--     分开存，清理预测只需要 TRUNCATE load_forecast，事实数据毫发无伤。
--
--  这是数据建模里"事实表 / 预测表 分离"的常见做法。
--
--  执行方式：把本文件内容粘进 mysql 客户端，或
--     mysql -u root -p power_load < db/02_forecast.sql
-- ============================================================

USE power_load;

CREATE TABLE IF NOT EXISTS load_forecast (
  id             BIGINT        NOT NULL AUTO_INCREMENT COMMENT '主键',
  region_code    VARCHAR(32)   NOT NULL               COMMENT '地区编码',
  region_name    VARCHAR(64)   NOT NULL               COMMENT '地区名称',

  -- 被预测的那个时刻
  forecast_ts    DATETIME      NOT NULL               COMMENT '预测的目标时刻',

  -- 模型算出来的结果
  predicted_load DECIMAL(12,3) NOT NULL               COMMENT '预测负荷(kW)',

  -- 喂给模型的输入。存下来是为了可追溯：
  -- 出问题时能回答"这条预测当时是用什么输入算出来的"
  input_temp     DECIMAL(5,2)  DEFAULT NULL           COMMENT '预测时使用的气温(℃)',
  input_hour     TINYINT       DEFAULT NULL           COMMENT '预测时使用的小时(0-23)',

  model_name     VARCHAR(64)   NOT NULL DEFAULT 'linear_regression' COMMENT '模型名称',
  model_r2       DECIMAL(6,4)  DEFAULT NULL           COMMENT '模型训练时的 R²，用于判断可信度',

  create_time    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '生成时间',

  PRIMARY KEY (id),

  -- 同一个地区、同一时刻的预测只保留最新一条。
  -- 有了这个唯一约束，Python 脚本可以反复运行而不会产生重复数据
  -- （脚本里用 INSERT ... ON DUPLICATE KEY UPDATE 配合它）。
  UNIQUE KEY uk_region_forecast_ts (region_code, forecast_ts),

  -- 前端会按"地区 + 时间范围"查预测曲线，这个索引正好服务它
  KEY idx_region_forecast_ts (region_code, forecast_ts)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='负荷预测结果（由 Python 线性回归模型写入）';

-- 验证
SELECT '--- 表清单 ---' AS info;
SHOW TABLES;
