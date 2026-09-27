# 电力负荷数据可视化平台

> 一个用于学习全栈链路的小型项目：**Spring Boot + MySQL + Vue3 + ECharts**，
> 数据取自公开的电力负荷场景，实现"采集 → 存储 → 聚合统计 → 可视化"的完整闭环。

<p>
  <img alt="Java" src="https://img.shields.io/badge/Java-17-orange">
  <img alt="Spring Boot" src="https://img.shields.io/badge/Spring%20Boot-3.3.5-brightgreen">
  <img alt="MySQL" src="https://img.shields.io/badge/MySQL-8.0-blue">
  <img alt="Vue" src="https://img.shields.io/badge/Vue-3.5-42b883">
  <img alt="ECharts" src="https://img.shields.io/badge/ECharts-5.5-aa344d">
</p>

---

## 一、这个项目解决什么问题

电力行业的负荷数据有三个特点：**采样频繁、数据量大、时间特征强**。
电网侧真正关心的不是"某一条读数是多少"，而是从数据里看出规律：

- 哪个地区、哪个时段用电压力最大？
- 用电是否均衡（峰谷差有多大）？
- 有没有明显偏离正常范围的异常点？

所以本项目做了两件事：**把原始负荷明细存下来**，并且**把它聚合成能直接看的指标和图表**。

### 已实现的功能

| 功能 | 说明 |
| --- | --- |
| 负荷明细查询 | 按地区 / 负荷阈值 / 时间区间筛选 |
| 异常点标记与展示 | 图表上用红色散点标出，表格里排在最前 |
| 地区维度聚合统计 | 平均 / 峰值 / 谷值 / 样本数 / 异常数 |
| 派生业务指标 | **峰谷差**、**负荷率**（由后端 Java 计算，数据库中不存在这两列） |
| 数据可视化看板 | 负荷趋势折线、地区对比柱状、日统计对比、指标表格 |
| 图表联动 | 点击地区柱子，趋势图只显示该地区 |

---

## 二、技术栈与选型理由

| 层次 | 技术 | 选型理由 |
| --- | --- | --- |
| 后端 | Spring Boot 3.3.5 (Java 17) | 生态成熟，内嵌 Tomcat 免去单独部署容器 |
| 持久层 | Spring Data JPA (Hibernate 6) | 单表 CRUD 由框架生成，只把精力花在复杂查询上 |
| 数据库 | MySQL 8.0 | 关系型、事务、索引能力齐全，与 DECIMAL 精度需求匹配 |
| 前端 | Vue 3 + Vite | 组合式 API 便于按功能拆分逻辑；Vite 冷启动快 |
| 图表 | ECharts 5 | 国内项目主流选择，折线/柱状/散点开箱即用 |
| 数据算法 | Python + scikit-learn | 做负荷预测的线性回归演示，结果回写数据库 |

**【你来写】为什么用 JPA 而不是 MyBatis？**
> 提示（用你自己的话说，2-3 句）：
> 我的场景是"简单查询多、复杂聚合少"，JPA 的派生查询（方法名即 SQL）
> 能省掉大量样板代码；只有少数聚合查询我用了 `@Query` 写 JPQL。
> 如果项目里复杂 SQL 占大多数，MyBatis 把 SQL 掌握在自己手里会更合适。

---

## 三、项目结构

```
test/
├── db/
│   ├── init.sql                 建库建表 + 样例数据（数据库的"配方"）
│   └── mysql.ps1                MySQL 启停脚本
├── _tools/                      一键脚本（环境/启动/自启）
├── power-load-platform/
│   ├── backend/                 Spring Boot 后端
│   │   └── src/main/java/com/example/powerload/
│   │       ├── entity/          实体类（对应数据库表）
│   │       ├── repository/      仓库层（只有接口，实现由 Spring 生成）
│   │       ├── service/         业务逻辑 + 事务
│   │       ├── controller/      接口层（只接请求、返回结果）
│   │       └── dto/             聚合查询结果投影
│   └── frontend/                Vue3 前端
│       └── src/
│           ├── api.js           所有后端接口封装
│           ├── App.vue          看板主界面（统一取数后分发给子组件）
│           ├── composables/     可复用逻辑（ECharts 封装）
│           └── components/      图表与表格组件
└── README.md
```

### 分层调用链

```
浏览器
  │  GET /api/stats/region-summary
  ▼
Controller（服务员）   只接收请求、组装返回，不碰数据库
  ▼
Service（厨师）        业务规则 + 事务；峰谷差/负荷率在这里计算
  ▼
Repository（库管）     只负责数据访问；派生查询由方法名生成 SQL
  ▼
Entity（ORM 映射）     描述 Java 对象 ↔ 数据库表 的对应关系
  ▼
MySQL  load_record / load_daily_stat
```

---

## 四、数据库设计

### `load_record` —— 原始负荷明细（事实表）

一行 = 某个地区在某个时刻的一条采样读数。

| 列 | 类型 | 含义 |
| --- | --- | --- |
| `id` | BIGINT 自增 | 主键 |
| `region_code` | VARCHAR(32) | 地区编码，如 GD-01 |
| `region_name` | VARCHAR(64) | 地区名称，如 广州 |
| `ts` | DATETIME | 采样时刻 |
| `load_kw` | DECIMAL(12,3) | 负荷值（千瓦） |
| `temperature` | DECIMAL(5,2) | 气温（℃），可空 |
| `is_anomaly` | TINYINT(1) | 1 = 算法判定为异常点 |
| `create_time` | DATETIME | 入库时间，数据库默认生成 |

**索引设计：**

| 索引 | 用途 |
| --- | --- |
| `idx_region_ts (region_code, ts)` | 联合索引。"查某地区某时间段"是最常见查询，最左前缀原则下它同时也能服务"只查某地区" |
| `idx_ts (ts)` | 支持跨地区按时间查询 |
| `idx_anomaly (is_anomaly)` | 异常检测页面只查 `is_anomaly = 1`，区分度低但过滤后数据量小 |

> **为什么用 DECIMAL 而不是 FLOAT/DOUBLE？**
> 负荷值、金额这类数字不能有误差。`DOUBLE` 是二进制浮点，`0.1 + 0.2` 会得到
> `0.30000000000000004`；`DECIMAL` 是十进制精确计算。Java 侧对应 `BigDecimal`。

### `load_daily_stat` —— 日统计结果（汇总表）

一行 = 某地区某一天的平均 / 峰值 / 谷值 / 异常数，由 Python 算法写回。

| 列 | 类型 | 含义 |
| --- | --- | --- |
| `region_code` | VARCHAR(32) | 地区编码 |
| `stat_date` | DATE | 统计日期 |
| `avg_load` / `max_load` / `min_load` | DECIMAL(12,3) | 日均 / 峰值 / 谷值 |
| `anomaly_cnt` | INT | 当日异常点个数 |
| `create_time` | DATETIME | 生成时间 |

唯一约束 `uk_region_date (region_code, stat_date)` —— **保证同地区同日期只有一条统计，防止算法重复跑时写入重复数据。**

> **为什么分两张表？** 这是"事实表 + 汇总表"的经典设计：
> 明细表数据量大、只增不改；汇总表数据量小、可重复生成、查询快。
> 看板上的趋势图查明细，概览指标查汇总，各取所需。

---

## 五、接口清单

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/api/health` | 环境自检，返回 MySQL 版本 / 库名 / 记录数 |
| GET | `/api/load-records` | 明细列表，可选 `?region=广州` |
| GET | `/api/load-records/high` | 高负荷记录，`?threshold=10000`，按负荷降序 |
| GET | `/api/load-records/anomalies` | 只查异常点（`is_anomaly = 1`） |
| GET | `/api/load-records/range` | 负荷区间查询，`?region=&min=&max=` |
| GET | `/api/load-records/count` | 总记录数 |
| GET | `/api/stats/daily` | 读日统计表，可选 `?regionCode=GD-01` |
| GET | `/api/stats/region-summary` | 按地区聚合：平均/峰值/谷值/异常数 |
| GET | `/api/stats/region-detail` | 聚合结果 + 派生指标（峰谷差、负荷率） |
| GET | `/api/stats/by-date` | 按日期聚合 |

**示例** `GET /api/stats/region-summary`：

```json
{
  "count": 2,
  "data": [
    {
      "regionCode": "GD-01",
      "regionName": "广州",
      "sampleCount": 5,
      "avgLoad": 10868.4,
      "maxLoad": 18990.100,
      "minLoad": 7210.800,
      "anomalyCount": 1
    }
  ]
}
```

---

## 六、关键实现细节

### 1. 聚合查询怎么返回？（DTO 投影）

聚合结果（平均、峰值）在数据库里是**现算出来的**，原表没有这些列，实体类也没有这些字段，
所以不能用实体类接收。这里用一个专门的 DTO：

```java
@Query("SELECT new com.example.powerload.dto.RegionSummaryDTO(" +
       "  r.regionCode, r.regionName, COUNT(r), " +
       "  AVG(r.loadKw), MAX(r.loadKw), MIN(r.loadKw), SUM(r.isAnomaly)) " +
       "FROM LoadRecord r " +
       "GROUP BY r.regionCode, r.regionName " +
       "ORDER BY AVG(r.loadKw) DESC")
List<RegionSummaryDTO> summarizeByRegion();
```

**踩过的坑：Hibernate 6 对构造器表达式的参数类型要求严格匹配，实测推断结果是：**

| 表达式 | 实际返回类型 |
| --- | --- |
| `COUNT(...)` | `Long` |
| `SUM(整数列)` | `Long` |
| **`AVG(...)`** | **`Double`** ← 最容易写错 |
| `MAX/MIN(小数列)` | `BigDecimal` |

把 `AVG` 写成 `BigDecimal` 会导致**应用启动直接失败**：

```
org.hibernate.query.SemanticException: Missing constructor for type 'RegionSummaryDTO'
```

排查方法：不猜类型，写一个临时的 `ApplicationRunner`，用 `Object[]` 接收查询结果，
把 `value.getClass().getName()` 打印出来看真实类型。

### 2. 派生指标在 Service 层算（不在 SQL 里算）

`峰谷差 = 最高负荷 − 最低负荷`、`负荷率 = 平均负荷 ÷ 最高负荷`。
这两个指标数据库里没有，是 Java 计算的 —— 这正是 Service 层存在的意义：
**它既不属于"接收 HTTP 请求"，也不属于"读写数据库"，必须有中间一层来放。**

### 3. 前端跨域怎么解决？（Vite 代理）

前端跑在 `5173`，后端跑在 `8080`，端口不同即跨域，浏览器默认拦截。
处理方式是在 `vite.config.js` 里配代理，让前端只请求"自己家"的地址：

```
浏览器 ──> 127.0.0.1:5173/api/...    （同源，不跨域）
               │
               └── Vite 转发 ──> 127.0.0.1:8080/api/...
```

浏览器看不到这次转发，因为 CORS 是**浏览器**的安全策略，管不到**服务器之间**的通信。
好处是后端一行代码都不用改。

> 生产环境一般不用代理，而是在后端配置 CORS 或让网关统一处理。
> 开发用代理只是因为它最简单、且不影响后端。

### 4. 前端数据流：单一数据源

所有接口请求集中在 `App.vue` 里执行一次，再通过 props 分发给各图表组件。

**为什么不各组件自己请求？** 同一个接口会被多个图用到，各请求一次就是重复请求；
出问题时也只有一个地方要查。筛选条件（如"只看深圳"）也能集中管理、统一影响多个图。

---

## 七、如何运行

### 环境要求

| 组件 | 版本 |
| --- | --- |
| JDK | 17+ |
| Maven | 3.9+ |
| MySQL | 8.0+ |
| Node.js | 20+ |
| Python | 3.10+（可选，仅负荷预测需要） |

### 步骤

**1）建库建表**

```bash
mysql -u root -p < db/init.sql
```

会创建 `power_load` 库、两张表，并插入样例数据。

**2）启动后端**

```bash
cd power-load-platform/backend
mvn spring-boot:run
```

看到 `Tomcat started on port 8080` 和 `Started PowerLoadApplication` 即为成功。

**3）启动前端**

```bash
cd power-load-platform/frontend
npm install          # 首次运行需要
npm run dev
```

**4）打开浏览器**

```
http://127.0.0.1:5173
```

> 注意：后端和前端要**同时运行**（两个终端窗口）。
> 前端页面报"加载失败"时，先确认后端是否在 8080 上运行。

### 数据库连接配置

配置在 `power-load-platform/backend/src/main/resources/application.yml`：

```yaml
url: jdbc:mysql://127.0.0.1:3306/power_load?...
username: root
password: root123456
```

> ⚠️ **这是本地演示库的密码，为了跑起来方便直接写在配置里。**
> 生产环境的正确做法是用环境变量或配置中心注入，不要把凭据提交到仓库。

---

## 八、当前数据的局限（诚实说明）

**这份仓库里的样例数据只有 8 条明细记录、1 个日期。** 因此：

1. **按日期聚合的接口只返回 1 行** —— 一个点是画不出"趋势线"的。
   所以前端的日统计图改成了**跨地区的平均/峰值/谷值对比**，这样现在就有信息量。
   等数据积累到多天，把横轴换成日期就是真正的趋势图。
2. **负荷预测只是流程演示**，8 条数据训练不出有预测能力的模型。
   代码的目的是演示"Python 读取数据库 → 训练 → 结果回写"这条链路。

> 我倾向于把这两点写在 README 里而不是藏起来 —— 面试时被问到"你这模型准不准"，
> 能主动说清"数据量决定它现在只能是演示"，比含糊其辞要安全得多。

---

## 九、可以继续改进的方向

- [ ] 接入真实的电力负荷公开数据集（如某省电网公开数据），把日期维度撑起来
- [ ] 引入定时任务，每天自动跑一次统计与预测
- [ ] 用 Docker Compose 一键启动 MySQL + 后端 + 前端
- [ ] 把明文密码改成环境变量注入
- [ ] 为接口补充单元测试
- [ ] 前端加上数据自动刷新（WebSocket 或轮询）

---

## 十、开发记录

项目从零搭建，完整记录了每一步的设计取舍与踩过的坑：

- SQL 逻辑执行顺序 `FROM → WHERE → GROUP BY → HAVING → SELECT → ORDER BY → LIMIT`
- `WHERE` 筛"行"、`HAVING` 筛"分组"，所以 `WHERE` 里不能写聚合函数
- ORM 的价值：把"行的搬运"交给框架，但复杂聚合仍需自己写 JPQL
- Hibernate 6 `AVG` 返回 `Double` 而非 `BigDecimal`（详见第六节）
- Vite 代理解决开发期跨域
- `spring.jackson.date-format` 只对 `java.util.Date` 生效，管不了 `LocalDateTime`
