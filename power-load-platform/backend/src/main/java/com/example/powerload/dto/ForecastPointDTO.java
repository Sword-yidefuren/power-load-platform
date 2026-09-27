package com.example.powerload.dto;

import java.math.BigDecimal;

/**
 * 第 7 步 · 预测曲线上的一个点
 *
 * 为什么不直接把 LoadForecast 实体返回给前端？
 *   实体里带着 id、createTime、modelName 这些"数据库管理字段"，
 *   前端画图只需要"时刻 + 预测值"，多传字段等于让接口语义变模糊。
 *   DTO 的作用就是把"数据库的形状"翻译成"接口需要的形状"。
 *   —— 这一点和第 5 步的 RegionSummaryDTO 是同一个思路。
 */
public class ForecastPointDTO {

    /** 时刻，格式化为 "2026-09-24 14:00" 这种给人看的样子 */
    private String time;

    private BigDecimal predictedLoad;

    private BigDecimal temperature;

    /**
     * 是不是模型"没见过的小时"。
     *
     * ★ 这个字段来源于第 7 步调试时的发现：历史数据只覆盖 0/1/2/12/14 点，
     *   让它预测其余 19 个小时属于"外推"，可信度更低。
     *   把这个信息传给前端，前端就能用虚线/浅色把这些点区分出来 ——
     *   这比"假装所有预测都一样可靠"要诚实得多。
     *
     *   面试可以聊：接口设计时把"数据可信度"作为一等公民暴露出来。
     */
    private boolean extrapolated;

    public ForecastPointDTO(String time, BigDecimal predictedLoad,
                            BigDecimal temperature, boolean extrapolated) {
        this.time = time;
        this.predictedLoad = predictedLoad;
        this.temperature = temperature;
        this.extrapolated = extrapolated;
    }

    public String getTime() {
        return time;
    }

    public BigDecimal getPredictedLoad() {
        return predictedLoad;
    }

    public BigDecimal getTemperature() {
        return temperature;
    }

    public boolean isExtrapolated() {
        return extrapolated;
    }
}
