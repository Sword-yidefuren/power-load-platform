-- ============================================================
--  电力负荷数据可视化平台 — 数据库初始化
--  对应面试话术："MySQL 存数据，Spring Boot 做后端"
-- ============================================================

CREATE DATABASE IF NOT EXISTS power_load
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_unicode_ci;

USE power_load;

-- ------------------------------------------------------------
-- 表 1：原始负荷数据（时序事实表）
--   一行 = 某个地区在某个时刻的负荷读数
-- ------------------------------------------------------------
DROP TABLE IF EXISTS load_record;

CREATE TABLE load_record (
  id           BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
  region_code  VARCHAR(32)  NOT NULL               COMMENT '地区编码，如 GD-01',
  region_name  VARCHAR(64)  NOT NULL               COMMENT '地区名称',
  ts           DATETIME     NOT NULL               COMMENT '采样时刻',
  load_kw      DECIMAL(12,3) NOT NULL              COMMENT '负荷值(kW)',
  temperature  DECIMAL(5,2) DEFAULT NULL           COMMENT '气温(℃)，可为空',
  is_anomaly   TINYINT(1)   NOT NULL DEFAULT 0     COMMENT '1=算法判定为异常',
  create_time  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '入库时间',
  PRIMARY KEY (id),
  -- 联合索引：(地区, 时间) —— 按地区查一段时间是最常见的查询
  KEY idx_region_ts (region_code, ts),
  -- 单独的时间索引 —— 支持跨地区查某个时间段
  KEY idx_ts (ts),
  -- 异常标记索引 —— 异常检测页面只查 is_anomaly=1
  KEY idx_anomaly (is_anomaly)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='电力负荷原始记录';

-- ------------------------------------------------------------
-- 表 2：日统计结果（聚合表，由 Python 算法写回）
--   体现"算法分析数据"这条 JD，也是"统计接口"的数据来源
-- ------------------------------------------------------------
DROP TABLE IF EXISTS load_daily_stat;

CREATE TABLE load_daily_stat (
  id          BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
  region_code VARCHAR(32)  NOT NULL               COMMENT '地区编码',
  stat_date   DATE         NOT NULL               COMMENT '统计日期',
  avg_load    DECIMAL(12,3) NOT NULL              COMMENT '日均负荷',
  max_load    DECIMAL(12,3) NOT NULL              COMMENT '日峰值负荷',
  min_load    DECIMAL(12,3) NOT NULL              COMMENT '日谷值负荷',
  anomaly_cnt INT          NOT NULL DEFAULT 0     COMMENT '当日异常点个数',
  create_time DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '生成时间',
  PRIMARY KEY (id),
  -- 唯一约束：同地区同日期只能有一条统计，防止算法重复写
  UNIQUE KEY uk_region_date (region_code, stat_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='日负荷统计与异常统计';

-- ------------------------------------------------------------
-- 造几条测试数据，让接口一开始就有东西可返回
-- ------------------------------------------------------------
INSERT INTO load_record (region_code, region_name, ts, load_kw, temperature, is_anomaly) VALUES
  ('GD-01', '广州', '2026-09-23 00:00:00', 8120.500, 28.5, 0),
  ('GD-01', '广州', '2026-09-23 01:00:00', 7640.200, 28.1, 0),
  ('GD-01', '广州', '2026-09-23 02:00:00', 7210.800, 27.8, 0),
  ('GD-01', '广州', '2026-09-23 12:00:00', 12380.400, 33.2, 0),
  ('GD-01', '广州', '2026-09-23 14:00:00', 18990.100, 35.6, 1),
  ('GD-02', '深圳', '2026-09-23 00:00:00', 9200.000, 29.0, 0),
  ('GD-02', '深圳', '2026-09-23 01:00:00', 8700.300, 28.7, 0),
  ('GD-02', '深圳', '2026-09-23 12:00:00', 14560.900, 34.1, 0);

INSERT INTO load_daily_stat (region_code, stat_date, avg_load, max_load, min_load, anomaly_cnt) VALUES
  ('GD-01', '2026-09-23', 9868.400, 18990.100, 7210.800, 1),
  ('GD-02', '2026-09-23', 10820.400, 14560.900, 8700.300, 0);

-- ------------------------------------------------------------
-- 验证
-- ------------------------------------------------------------
SELECT '--- 表清单 ---' AS info;
SHOW TABLES;

SELECT '--- load_record 行数 ---' AS info;
SELECT COUNT(*) AS rows_in_load_record FROM load_record;

SELECT '--- 统计查询示例：各地区负荷概览 ---' AS info;
SELECT
  lr.region_code,
  lr.region_name,
  COUNT(*)              AS sample_cnt,
  ROUND(AVG(lr.load_kw), 2) AS avg_load,
  ROUND(MAX(lr.load_kw), 2) AS peak_load,
  SUM(lr.is_anomaly)    AS anomaly_cnt,
  ds.avg_load           AS stat_avg_load
FROM load_record lr
LEFT JOIN load_daily_stat ds
  ON ds.region_code = lr.region_code
 AND ds.stat_date = DATE(lr.ts)
GROUP BY lr.region_code, lr.region_name, ds.avg_load
ORDER BY avg_load DESC;
