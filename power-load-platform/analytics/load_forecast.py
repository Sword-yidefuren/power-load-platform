# -*- coding: utf-8 -*-
"""
第 7 步 · 电力负荷预测（线性回归）
================================================

这个脚本干的事，一句话说清：

    从 MySQL 读历史负荷  ->  训练线性回归模型  ->  预测未来 24 小时  ->  写回 MySQL

【必须先读：这个模型的能力边界】

    训练数据只有 8 条记录、1 个日期。所以：

      1. 它做不出有实际预测能力的模型 —— 8 个样本拟合 3 个特征，
         模型会把噪声也"背下来"（这叫过拟合：已知数据上表现好，新数据就崩）。
      2. 它的价值在于证明"算法能接进这条数据链路"：
         读库 -> 建模 -> 预测 -> 回写 -> 前端展示。

    真正的短期负荷预测需要：至少几个月的历史数据、工作日/节假日标记、
    滞后负荷、温度累积效应等特征。

【模型公式】

    负荷 = 截距
         + is_gz * 广州的基准差异      <- 地区基准负荷不同
         + b_hour * 小时               <- 用电的作息规律
         + b_temp * 气温               <- 空调带来的降温负荷

    其中 b_temp 是最有业务含义的系数：**气温每升高 1 度，负荷增加多少 kW**。

运行方式：
    python power-load-platform/analytics/load_forecast.py
"""

import os
import sys
from datetime import datetime, timedelta

# ============================================================
#  Windows 控制台编码保险
# ============================================================
#  中文 Windows 的控制台默认编码是 GBK，而 GBK 里没有上标 ² 之类的字符，
#  一旦 print 到终端就会抛：
#      UnicodeEncodeError: 'gbk' codec can't encode character '\xb2'
#
#  两种应对（这里两种都做了，双保险）：
#    1. 把所有 print 的内容换成 ASCII 安全写法（R^2 而不是 R²）
#    2. 在入口处尝试把 stdout 切成 UTF-8，失败也不影响运行
#      （reconfigure 是 Python 3.7+ 的能力；被重定向到文件时可能不支持）
try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

import numpy as np
import pandas as pd
from sqlalchemy import create_engine, text

from sklearn.linear_model import LinearRegression
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.model_selection import LeaveOneOut, cross_val_predict

# 画图：用非交互后端，脚本才能在没有窗口的环境下跑完
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

# ---------- 中文字体：不设置的话图上中文会变成一个个方框 ----------
for _font in ("Microsoft YaHei", "SimHei", "SimSun"):
    matplotlib.rcParams["font.sans-serif"] = [_font]
    break
matplotlib.rcParams["axes.unicode_minus"] = False  # 让负号正常显示

# ============================================================
#  配置
# ============================================================

DB_USER = "root"
DB_PASS = "root123456"
DB_HOST = "127.0.0.1"
DB_PORT = 3306
DB_NAME = "power_load"

MODEL_NAME = "linear_regression"

# 输出的图和结果放在脚本旁边，方便查看
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "output")


def make_engine():
    """建数据库连接。charset=utf8mb4 保证中文不出乱码。"""
    url = (
        f"mysql+pymysql://{DB_USER}:{DB_PASS}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
        f"?charset=utf8mb4"
    )
    return create_engine(url, pool_pre_ping=True)


def ensure_forecast_table(engine):
    """
    确保预测表存在。

    表结构定义在 db/02_forecast.sql 里 —— 这里再判断一次是为了
    让脚本能独立跑（不用先手动执行 SQL 文件）。
    """
    ddl = """
    CREATE TABLE IF NOT EXISTS load_forecast (
      id             BIGINT        NOT NULL AUTO_INCREMENT,
      region_code    VARCHAR(32)   NOT NULL,
      region_name    VARCHAR(64)   NOT NULL,
      forecast_ts    DATETIME      NOT NULL,
      predicted_load DECIMAL(12,3) NOT NULL,
      input_temp     DECIMAL(5,2)  DEFAULT NULL,
      input_hour     TINYINT       DEFAULT NULL,
      model_name     VARCHAR(64)   NOT NULL DEFAULT 'linear_regression',
      model_r2       DECIMAL(6,4)  DEFAULT NULL,
      create_time    DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (id),
      UNIQUE KEY uk_region_forecast_ts (region_code, forecast_ts),
      KEY idx_region_forecast_ts (region_code, forecast_ts)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
    """
    with engine.begin() as conn:
        conn.execute(text(ddl))


def load_history(engine):
    """把历史明细读成 DataFrame。"""
    sql = text(
        """
        SELECT region_code, region_name, ts, load_kw, temperature, is_anomaly
        FROM load_record
        ORDER BY region_code, ts
        """
    )
    with engine.connect() as conn:
        df = pd.read_sql(sql, conn)

    # 确保类型正确（DECIMAL 读进来可能变成 object）
    df["load_kw"] = pd.to_numeric(df["load_kw"])
    df["temperature"] = pd.to_numeric(df["temperature"])
    df["ts"] = pd.to_datetime(df["ts"])
    return df


def build_features(df):
    """
    特征工程：把"原始列"变成"模型能理解的特征"。

    这一步是机器学习里最花时间、也最影响效果的部分。这里做两件事：

      1. 从时间戳里抽出"小时" —— 因为用电是按作息走的，14 点和 2 点的负荷完全不同
      2. 把地区名变成 0/1 的哑变量（is_gz）—— 模型只认数字，不认"广州"这个字符串

    为什么不用 One-Hot 编码的通用写法（pd.get_dummies）？
    因为只有两个地区，一个 0/1 列就够了（一个变量能表达两种情况）。
    地区多了才需要多列。
    """
    out = df.copy()
    out["hour"] = out["ts"].dt.hour
    out["is_gz"] = (out["region_code"] == "GD-01").astype(int)
    return out


def train_model(feat, feature_cols):
    """
    训练线性回归，并给出"诚实的"效果评估。

    ★ 关键点：这里用 留一法交叉验证（Leave-One-Out）来评估，而不是
      "拿全部数据训练、再拿同一批数据算 R²"。

      为什么？后者是自我欺骗 —— 模型见过答案再考试，分数当然高。
      留一法的做法是：每次拿走 1 条不参与训练，用它当"考卷"，
      重复 N 次。这样算出来的分数才能反映"遇到没见过的数据会怎样"。

      数据只有 8 条时，这是唯一还算靠谱的评估方式。
    """
    feature_cols = list(feature_cols)
    X = feat[feature_cols].values
    y = feat["load_kw"].values

    model = LinearRegression()
    model.fit(X, y)

    # --- 训练集上的表现（会偏乐观，只作参考）---
    y_fit = model.predict(X)
    r2_train = r2_score(y, y_fit)

    # --- 留一法交叉验证（诚实的表现）---
    loo = LeaveOneOut()
    y_loo = cross_val_predict(model, X, y, cv=loo)
    r2_loo = r2_score(y, y_loo)
    rmse_loo = float(np.sqrt(mean_squared_error(y, y_loo)))
    mae_loo = float(mean_absolute_error(y, y_loo))

    coefs = dict(zip(feature_cols, model.coef_))
    return {
        "model": model,
        "feature_cols": feature_cols,
        "intercept": float(model.intercept_),
        "coefs": coefs,
        "r2_train": float(r2_train),
        "r2_loo": float(r2_loo),
        "rmse_loo": rmse_loo,
        "mae_loo": mae_loo,
        "y_true": y,
        "y_fit": y_fit,
        "y_loo": y_loo,
    }


def compare_two_models(feat):
    """
    ★ 这一段是整个脚本最有价值的"工程判断"，请重点读。

    背景：初版模型同时用了 hour（小时）和 temperature（气温）两个特征，
    跑出来的系数是：

        b[hour]        = -498.6    <- 负数！意思是"时间越晚负荷越低"
        b[temperature] =  2245.0    <- 比数据真实斜率（约 1531）高出 47%

    两个系数都不符合常识。原因在于这份数据里：

        气温从 27.8 -> 35.6 升高的同时，小时也从 0/1/2 变成了 12/14。
        实测 corr(hour, temperature) = 0.971 —— 两个特征几乎是同一个信息。

    模型于是分不清"负荷高"该归功于气温还是归功于时间，就随意分配权重：
    为了拟合，它把气温系数吹大、把时间系数压成负的，只要两者加起来对就行。

    这在统计上叫"多重共线性"（multicollinearity），典型症状就是：
        整体拟合很好（R² 高），但单个系数完全不可解释。

    这里做的事就是：去掉冗余特征（hour），只保留业务上有明确物理含义的气温，
    然后对比两个模型。你会看到 R² 几乎没变，但系数回到合理范围 ——
    说明 hour 提供的信息是重复的，去掉它不损失精度，却换回了可解释性。

    面试可以这么讲：
        "我发现两个特征相关度 0.97，导致系数不可解释（小时系数甚至是负的）。
         去掉冗余特征后 R² 基本不变，但系数回到符合物理常识的范围，
         所以我选了可解释的那个模型。"
    """
    print("\n[4] 模型对比：为什么要去掉 hour 特征")
    print("    " + "-" * 62)
    print(f"    {'模型':<36}{'训练R^2':>10}{'留一R^2':>10}")
    print("    " + "-" * 62)

    cols_a = ["is_gz", "hour", "temperature"]
    cols_b = ["is_gz", "temperature"]

    bundle_a = train_model(feat, cols_a)
    bundle_b = train_model(feat, cols_b)

    print(f"    {'A: is_gz + hour + temperature':<36}"
          f"{bundle_a['r2_train']:>10.4f}{bundle_a['r2_loo']:>10.4f}")
    print(f"    {'B: is_gz + temperature  (主模型)':<36}"
          f"{bundle_b['r2_train']:>10.4f}{bundle_b['r2_loo']:>10.4f}")
    print("    " + "-" * 62)

    print("\n    两个模型的系数对照（注意 hour 的符号和 temperature 的大小）：")
    for key in ("is_gz", "hour", "temperature"):
        va = bundle_a["coefs"].get(key)
        vb = bundle_b["coefs"].get(key)
        sa = f"{va:>12,.1f}" if va is not None else f"{'(已去掉)':>12}"
        sb = f"{vb:>12,.1f}" if vb is not None else f"{'(已去掉)':>12}"
        print(f"      {key:<14} A: {sa}    B: {sb}")

    # 用数据直接算出的"真实斜率"当参照物
    gz = feat[feat["region_code"] == "GD-01"].sort_values("ts")
    if len(gz) >= 2 and gz["temperature"].iloc[-1] != gz["temperature"].iloc[0]:
        real_slope = (
            (gz["load_kw"].iloc[-1] - gz["load_kw"].iloc[0])
            / (gz["temperature"].iloc[-1] - gz["temperature"].iloc[0])
        )
        print(f"\n      参照：从数据直接算的真实斜率 = {real_slope:,.0f} kW/度")
        print(f"            模型 A 给 {bundle_a['coefs']['temperature']:,.0f}，"
              f"模型 B 给 {bundle_b['coefs']['temperature']:,.0f}")

    print("\n    结论：去掉 hour 后 R^2 变化很小，但系数回到合理范围 ——")
    print("          说明 hour 的信息与气温高度重复。去掉它不损失精度，")
    print("          却换回了「系数可解释」这个更有价值的东西。")

    return bundle_a, bundle_b  # A 用来对比，B（可解释的）作为主模型

def make_future_temperature(region_hist, target_date, hours=24):
    """
    造未来 24 小时的"气温输入"。

    ★ 这里必须诚实：我们没有天气预报数据，气温是按历史规律模拟的。
      真实项目里这一步应该是：调用气象 API / 读气象数据库拿预报值。

    第一版这里有两个坑，都是跑出不合常理的结果后才发现的：

    坑 1：随机波动幅度用错
        一开始用 overall_std = 2.6 度当波动幅度。那是"跨时段"的温差
        （凌晨 27.8 到午后 35.6 的差距），拿来当"同一时段内的波动"太大了，
        模拟出的凌晨气温从 28.6 跳到 31.1，预测负荷因此在凌晨出现假高峰。

    坑 2：把气温造到历史范围之外
        既然模型是"负荷 = f(气温)"，那么输入气温一旦超出训练时见过的
        27.8~35.6 这个区间，模型就是在**外推**，结果不可信
        （实测出现过预测谷值 2158 kW 这种物理上不可能的数字）。
        所以这里把生成的气温**夹紧在历史范围内**。

    改用平滑的日周期曲线（正弦形状），既能表达"凌晨低、午后高"的规律，
    又保证了相邻小时缓慢变化 —— 这两点都符合真实气温的行为。
    """
    temps = region_hist["temperature"].astype(float)

    if len(temps) >= 2:
        t_peak = float(temps.max())    # 历史最高气温
        t_valley = float(temps.min())  # 历史最低气温
    else:
        t_peak = t_valley = float(temps.mean())

    # 用余弦波做平滑日周期：12 点附近最热，0 点附近最冷。
    # 形状取历史观测到的最高/最低气温作为上下界，因此天然落在训练范围内。
    rng = np.random.default_rng(seed=42)  # 固定随机种子，保证结果可复现
    rows = []
    for h in range(hours):
        # ((-cos) + 1) / 2 在 h=0 时为 0、h=12 时为 1，正好是"热"的形状
        weight = (1 - np.cos(2 * np.pi * h / 24)) / 2
        temp = t_valley + (t_peak - t_valley) * weight
        temp += rng.normal(0, 0.25)          # 一点点随机波动，模拟天气不完全重复
        temp = float(np.clip(temp, t_valley - 0.5, t_peak + 0.5))  # 夹紧，避免外推
        ts = datetime.combine(target_date, datetime.min.time()) + timedelta(hours=h)
        rows.append({
            "forecast_ts": ts,
            "hour": h,                       # ← 与训练特征同名
            "temperature": round(temp, 2),   # ← 与训练特征同名
        })
    return pd.DataFrame(rows)


def predict_and_collect(history, bundle, target_date):
    """对每个地区预测未来 24 小时，收集成一张结果表。"""
    model = bundle["model"]
    feature_cols = bundle["feature_cols"]

    frames = []
    for (code, name) in history[["region_code", "region_name"]].drop_duplicates().values:
        is_gz = 1 if code == "GD-01" else 0

        region_hist = history[history["region_code"] == code]
        fut = make_future_temperature(region_hist, target_date)
        fut["is_gz"] = is_gz

        # 用特征名显式取列 —— 顺序和训练时一致，不然模型会算错
        X_future = fut[feature_cols].values
        pred = model.predict(X_future)

        # 物理约束：负荷不可能是负数。
        # 模型外推时可能算出负值，这里兜底成 0 并在下面报警。
        # 真实系统里"出现负预测"本身就是模型不可用的信号。
        pred = np.maximum(pred, 0.0)

        fut["region_code"] = code
        fut["region_name"] = name
        fut["predicted_load"] = np.round(pred, 3)
        frames.append(fut[["region_code", "region_name", "forecast_ts",
                           "predicted_load", "temperature", "hour"]])

    return pd.concat(frames, ignore_index=True)


def write_forecast(engine, result_df, r2_loo):
    """
    把预测结果写回数据库。

    ★ 用 INSERT ... ON DUPLICATE KEY UPDATE（常说的 upsert）而不是纯 INSERT。

      为什么？因为 load_forecast 上有唯一约束 (region_code, forecast_ts)。
      纯 INSERT 第二次运行时就会撞唯一键报错；而 upsert 的语义是
      "有就更新，没有就插入" —— 脚本因此可以**反复运行**，这是很实用的性质。

      这也是"幂等"（idempotent）这个工程概念的具体体现：
      同一个操作执行一次和执行十次，结果一样。
    """
    sql = text(
        """
        INSERT INTO load_forecast
            (region_code, region_name, forecast_ts, predicted_load,
             input_temp, input_hour, model_name, model_r2)
        VALUES
            (:region_code, :region_name, :forecast_ts, :predicted_load,
             :input_temp, :input_hour, :model_name, :model_r2)
        ON DUPLICATE KEY UPDATE
            predicted_load = VALUES(predicted_load),
            input_temp     = VALUES(input_temp),
            input_hour     = VALUES(input_hour),
            model_r2       = VALUES(model_r2),
            create_time    = CURRENT_TIMESTAMP
        """
    )

    rows = []
    for r in result_df.itertuples(index=False):
        rows.append({
            "region_code": r.region_code,
            "region_name": r.region_name,
            "forecast_ts": r.forecast_ts,
            "predicted_load": float(r.predicted_load),
            "input_temp": float(r.temperature),   # 数据库列叫 input_temp
            "input_hour": int(r.hour),            # 数据库列叫 input_hour
            "model_name": MODEL_NAME,
            "model_r2": round(float(r2_loo), 4),
        })

    with engine.begin() as conn:
        conn.execute(sql, rows)
    return len(rows)


def plot_results(history, bundle_a, bundle_b, result_df, out_path):
    """画三张图：规律找得准不准、预测长什么样、两个模型的系数对比。"""
    fig, axes = plt.subplots(1, 3, figsize=(19, 5.5))

    # ---------- 左图：气温 vs 负荷 的散点 + 拟合直线 ----------
    ax = axes[0]
    for code, color, marker in (("GD-01", "#e74c3c", "o"), ("GD-02", "#2980b9", "s")):
        sub = history[history["region_code"] == code]
        ax.scatter(sub["temperature"], sub["load_kw"], s=90, alpha=0.85,
                   color=color, marker=marker, label=sub["region_name"].iloc[0],
                   edgecolors="white", linewidths=1.2)

    # 拟合线：固定 is_gz，看"负荷 随 气温"怎么走。
    # 注意：主模型（B）里没有 hour 特征，所以这里要判断一下再算，
    # 否则会 KeyError —— 特征变了，画图的公式也要跟着变。
    temp_grid = np.linspace(history["temperature"].min() - 0.5,
                            history["temperature"].max() + 0.5, 50)
    coefs = bundle_b["coefs"]
    hour_term = coefs.get("hour", 0.0) * float(history["ts"].dt.hour.mean())
    for is_gz, color in ((1, "#e74c3c"), (0, "#2980b9")):
        y_line = (bundle_b["intercept"] + coefs["is_gz"] * is_gz
                  + coefs["temperature"] * temp_grid
                  + hour_term)
        ax.plot(temp_grid, y_line, color=color, linewidth=2, alpha=0.7)

    ax.set_xlabel("气温 (℃)")
    ax.set_ylabel("负荷 (kW)")
    ax.set_title(f"气温与负荷的关系（主模型 R^2={bundle_b['r2_train']:.3f}）")
    ax.legend()
    ax.grid(alpha=0.3)

    # ---------- 中图：历史实际 + 未来预测 ----------
    ax = axes[1]
    for code, color in (("GD-01", "#e74c3c"), ("GD-02", "#2980b9")):
        sub = history[history["region_code"] == code].sort_values("ts")
        ax.plot(sub["ts"], sub["load_kw"], marker="o", color=color,
                label=f"{sub['region_name'].iloc[0]} 实际", linewidth=2)

    for code, color in (("GD-01", "#e74c3c"), ("GD-02", "#2980b9")):
        sub = result_df[result_df["region_code"] == code].sort_values("forecast_ts")
        ax.plot(sub["forecast_ts"], sub["predicted_load"], marker="^",
                color=color, linestyle="--", alpha=0.85, linewidth=2,
                label=f"{sub['region_name'].iloc[0]} 预测")

    ax.set_xlabel("时间")
    ax.set_ylabel("负荷 (kW)")
    ax.set_title("实际负荷 与 未来 24 小时预测")
    ax.legend(fontsize=9)
    ax.grid(alpha=0.3)

    # ---------- 右图：两个模型的系数对比（说明为什么要去掉 hour）----------
    ax = axes[2]
    names = ["is_gz", "hour", "temperature"]
    a_vals = [bundle_a["coefs"].get(n, 0.0) for n in names]
    b_vals = [bundle_b["coefs"].get(n, 0.0) for n in names]

    xpos = np.arange(len(names))
    width = 0.36
    ax.bar(xpos - width / 2, a_vals, width,
           label="模型A: +hour", color="#e67e22", alpha=0.9)
    ax.bar(xpos + width / 2, b_vals, width,
           label="模型B: 主模型", color="#27ae60", alpha=0.9)
    ax.axhline(0, color="#555", linewidth=1)
    ax.set_xticks(xpos)
    ax.set_xticklabels(names)
    ax.set_ylabel("系数值")
    ax.set_title("去掉冗余特征后系数回到合理范围")
    ax.legend(fontsize=9)
    ax.grid(alpha=0.3, axis="y")

    # 标注：hour 在模型 A 里是负的，而在模型 B 里已被去掉
    ax.annotate("负数：\n时间越晚负荷越低\n（与常识矛盾）",
                xy=(1 - width / 2, a_vals[1]),
                xytext=(1.15, min(a_vals) * 0.75),
                fontsize=8, color="#c0392b",
                arrowprops=dict(arrowstyle="->", color="#c0392b", lw=1))

    fig.autofmt_xdate()
    fig.tight_layout()
    fig.savefig(out_path, dpi=110, bbox_inches="tight")
    plt.close(fig)


def business_summary(result_df):
    """
    把预测结果加工成"业务指标"。

    这一步和 Java 后端 StatService 里算峰谷差、负荷率是同一件事 ——
    模型输出的是原始数字，能不能变成业务语言，取决于这一层。
    """
    out = []
    for (code, name), sub in result_df.groupby(["region_code", "region_name"]):
        peak = float(sub["predicted_load"].max())
        valley = float(sub["predicted_load"].min())
        avg = float(sub["predicted_load"].mean())
        out.append({
            "region": name,
            "peak": peak,
            "valley": valley,
            "avg": avg,
            "peak_valley_diff": peak - valley,
            "load_rate": round(avg / peak, 4) if peak > 0 else 0.0,
            "peak_hour": int(sub.loc[sub["predicted_load"].idxmax(), "hour"]),
        })
    return out


def main():
    print("=" * 68)
    print("  电力负荷预测 · 线性回归")
    print("=" * 68)

    engine = make_engine()
    ensure_forecast_table(engine)

    # ---------- 1. 读数据 ----------
    history = load_history(engine)
    print(f"\n[1] 读取历史数据：{len(history)} 条")
    print(f"    地区：{', '.join(sorted(history['region_name'].unique()))}")
    print(f"    时间范围：{history['ts'].min()} ~ {history['ts'].max()}")
    print(f"    气温范围：{history['temperature'].min()} ~ {history['temperature'].max()} ℃")

    if len(history) < 3:
        print("\n数据太少，无法训练模型。请先执行 db/init.sql 造样例数据。")
        sys.exit(1)

    # ---------- 2. 特征工程 + 训练（含双模型对比）----------
    feat = build_features(history)

    print(f"\n[2] 数据集概览")
    print(f"    样本数：{len(feat)}")
    print(f"    特征相关性检查：")
    corr_ht = feat["hour"].corr(feat["temperature"])
    print(f"      corr(hour, temperature) = {corr_ht:+.3f}"
          + ("   ← 高度相关！两个特征信息重复" if abs(corr_ht) > 0.8 else ""))
    for col in ("is_gz", "hour", "temperature"):
        print(f"      corr({col:<12}, load_kw) = {feat[col].corr(feat['load_kw']):+.3f}")

    # 对比两个模型
    bundle_a, bundle_b = compare_two_models(feat)
    bundle = bundle_b  # 默认主模型 = B（可解释）

    # ============================================================
    #  ★ 一个真实的取舍：两个模型各有什么用，预测该用哪个
    # ============================================================
    #  模型 A（含 hour）：训练集 R² 更高，但 hour 系数是 -498.6
    #      它意味着"每小时降 500 kW"。历史上只观测到 0/1/2/12/14 点，
    #      一旦让它预测 3、4、5 点这些没见过的时刻，就会用这个负斜率一路外推，
    #      实测出现过谷值 2158 kW 这种物理上不可能的数字。
    #      => 结论：这个系数是在拟合噪声，不能用于外推。
    #
    #  模型 B（只含 temperature）：系数干净可解释，预测值也始终在合理范围。
    #      代价是它不知道"几点钟"，所以曲线形状跟着气温走，画不出负荷的
    #      时间滞后特征（真实负荷峰值一般滞后于气温峰值几小时）。
    #
    #  => 决策：**预测用 B**。
    #     理由：一个会输出负数或物理不可能值的模型，比一个"形状不够好"的
    #           模型危险得多。准确性可以妥协，物理合理性不能。
    #     这是工程判断，不是数学结论 —— 面试可以聊这个权衡。
    model_for_forecast = bundle_b

    print(f"\n[3] 用于预测的模型：B（特征：{', '.join(model_for_forecast['feature_cols'])}）")
    print(f"    截距 a = {model_for_forecast['intercept']:,.1f}")
    for k, v in model_for_forecast["coefs"].items():
        print(f"    系数 b[{k}] = {v:,.3f}")

    print(f"\n    ★ 业务解读：气温每升高 1℃，负荷增加约 "
          f"{model_for_forecast['coefs']['temperature']:,.0f} kW")
    print(f"      （这就是电力行业说的「降温负荷」）")
    print(f"    ⚠ 但对比模型 A 给的 {bundle_a['coefs']['temperature']:,.0f}，"
          f"两者差了一倍 ——")
    print(f"      在 8 条样本下系数本身就不稳定，这个数字只能当参考。")
    print(f"\n    为什么不用 A 做预测？（A 的训练集 R² 更高）")
    print(f"      A 的 hour 系数 = {bundle_a['coefs']['hour']:,.1f}，"
          f"意思是「每小时降 {abs(bundle_a['coefs']['hour']):,.0f} kW」。")
    print(f"      历史只观测到 0/1/2/12/14 点，让它预测 3/4/5 点这些没见过的时刻，")
    print(f"      它会用这个负斜率一路外推，实测出现了谷值 2158 kW 这种不可能的值。")
    print(f"      => 一个会输出物理上不可能结果的模型，比形状不完美的模型更危险。")

    print(f"\n[3b] 模型效果评估（{len(history)} 个样本）")
    print(f"    模型A 训练集 R^2 = {bundle_a['r2_train']:.4f} | "
          f"留一法 R^2 = {bundle_a['r2_loo']:.4f}")
    print(f"    模型B 训练集 R^2 = {bundle_b['r2_train']:.4f} | "
          f"留一法 R^2 = {bundle_b['r2_loo']:.4f}")
    print(f"    ⚠ 只有 {len(history)} 条数据，这些数字不稳定，"
          f"模型的意义在于跑通流程而非实际预测")

    # ---------- 3. 预测未来 24 小时 ----------
    last_ts = history["ts"].max()
    target_date = (last_ts + timedelta(days=1)).date()
    print(f"\n[5] 预测目标日期：{target_date}（共 24 小时 × "
          f"{history['region_name'].nunique()} 个地区）")

    result_df = predict_and_collect(history, model_for_forecast, target_date)

    # ---------- 4. 写回数据库 ----------
    n = write_forecast(engine, result_df, model_for_forecast["r2_loo"])
    print(f"\n[6] 已写回数据库 load_forecast 表：{n} 行")
    print(f"    （使用 upsert，脚本可反复运行不会产生重复数据）")

    # ---------- 5. 业务指标 ----------
    print("\n[7] 预测结果的业务指标（未来 24 小时）")
    print(f"    {'地区':<6}{'平均':>12}{'峰值':>12}{'谷值':>12}"
          f"{'峰谷差':>12}{'负荷率':>10}{'峰值时刻':>10}")
    for row in business_summary(result_df):
        print(f"    {row['region']:<6}{row['avg']:>12,.0f}{row['peak']:>12,.0f}"
              f"{row['valley']:>12,.0f}{row['peak_valley_diff']:>12,.0f}"
              f"{row['load_rate']:>10.2%}{row['peak_hour']:>8}时")

    # ---------- 5b. 合理性检查：预测曲线像不像真实的负荷曲线 ----------
    #  一个真实负荷曲线必然是"凌晨低谷、白天高峰"。
    #  如果预测出来的凌晨比白天还高，说明模型有问题（缺特征或输入不合理）。
    print("\n[7b] 预测合理性检查")
    for code in result_df["region_code"].unique():
        sub = result_df[result_df["region_code"] == code]
        night = sub[sub["hour"].isin([2, 3, 4])]["predicted_load"].mean()
        day = sub[sub["hour"].isin([12, 13, 14])]["predicted_load"].mean()
        name = sub["region_name"].iloc[0]
        ok = "合理（凌晨低谷）" if night < day else "不合理！凌晨高于白天"
        print(f"    {name}：凌晨(2-4点)均值 {night:,.0f} kW，"
              f"白天(12-14点)均值 {day:,.0f} kW  ->  {ok}")

    # ---------- 5c. 训练数据覆盖检查（自动化版的"眼力"）----------
    #  这是今天调试时最耗时间的一件事，所以把它变成脚本的一部分：
    #  模型只能"内插"，不能"外推"。如果预测用的输入超出了训练时见过的范围，
    #  结果就不可信。这里一次性把两种情况都报出来。
    print("\n[7c] 数据覆盖检查（模型外推风险预警）")

    # 1) 小时覆盖：模型只在见过的时刻上可靠
    seen_hours = sorted(feat["hour"].unique().tolist())
    predict_hours = sorted(result_df["hour"].unique().tolist())
    missing = [h for h in predict_hours if h not in seen_hours]
    print(f"    历史观测到的小时：{seen_hours}")
    print(f"    预测需要的小时  ：{predict_hours[0]} ~ {predict_hours[-1]}（共 {len(predict_hours)} 个）")
    if missing:
        print(f"    ⚠ 有 {len(missing)} 个小时模型从未见过（如 {missing[:6]}...），")
        print(f"      这些时刻的预测属于【外推】，可信度明显低于见过的时刻。")
        print(f"      这就是为什么只含气温的模型比含 hour 的模型更安全：")
        print(f"      它不依赖「小时」这个特征，也就不会因为外推而崩掉。")
    else:
        print(f"    ✓ 预测用到的所有小时都在历史覆盖范围内")

    # 2) 气温覆盖：输入气温不能超出训练范围
    t_lo, t_hi = float(feat["temperature"].min()), float(feat["temperature"].max())
    p_lo = float(result_df["temperature"].min())
    p_hi = float(result_df["temperature"].max())
    print(f"    历史气温范围：{t_lo:.1f} ~ {t_hi:.1f} ℃")
    print(f"    预测气温范围：{p_lo:.1f} ~ {p_hi:.1f} ℃")
    if p_lo < t_lo - 0.6 or p_hi > t_hi + 0.6:
        print(f"    ⚠ 预测气温超出了训练范围 -> 存在外推风险！")
    else:
        print(f"    ✓ 预测气温落在训练范围内，不存在外推")

    # 3) 负值/异常值检查
    neg = int((result_df["predicted_load"] < 0).sum())
    hist_min = float(history["load_kw"].min())
    too_low = int((result_df["predicted_load"] < hist_min * 0.5).sum())
    print(f"    预测出现负值：{neg} 个   |   低于历史最小值一半的：{too_low} 个")
    if neg or too_low:
        print(f"    ⚠ 出现了物理上可疑的预测值，说明模型或输入有问题")
    else:
        print(f"    ✓ 所有预测值都在物理合理的范围内")

    # 4) 形状吻合度：预测曲线的形状和真实曲线像不像
    #    用"预测值 vs 实际值"的相关系数衡量（不是 R²，只看形状是否同涨同落）
    try:
        merged = result_df.merge(
            history[["region_code", "ts", "load_kw"]],
            left_on=["region_code", "hour"],
            right_on=["region_code", history["ts"].dt.hour],
            how="inner",
        )
        if len(merged) >= 3:
            shape_r = merged["predicted_load"].corr(merged["load_kw"])
            print(f"    形状吻合度（预测 vs 实际，在重合时刻上）corr = {shape_r:+.3f}")
            if shape_r < 0.5:
                print(f"      -> 偏低：说明预测曲线的走势和真实曲线不太一致")
    except Exception as e:
        print(f"    （形状检查跳过：{e}）")

    # ---------- 6. 出图 ----------
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    img_path = os.path.join(OUTPUT_DIR, "forecast_result.png")
    plot_results(history, bundle_a, bundle_b, result_df, img_path)
    print(f"\n[8] 图表已保存：{img_path}")

    csv_path = os.path.join(OUTPUT_DIR, "forecast_24h.csv")
    result_df.to_csv(csv_path, index=False, encoding="utf-8-sig")
    print(f"    预测数据已导出：{csv_path}")

    print("\n" + "=" * 68)
    print("  完成。前端可通过后端接口读取 load_forecast 展示预测曲线。")
    print("=" * 68)


if __name__ == "__main__":
    main()
