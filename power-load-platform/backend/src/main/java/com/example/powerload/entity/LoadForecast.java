package com.example.powerload.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.math.BigDecimal;
import java.time.LocalDateTime;

/**
 * 第 7 步 · 实体类 —— 对应表 load_forecast（预测结果表）
 *
 * 这张表由 Python 的线性回归脚本写入，Java 侧只负责读出来给前端展示。
 * 注意它和另外两张表的职责划分：
 *
 *   load_record    : 已经发生的事实（明细）
 *   load_daily_stat: 已经算好的汇总
 *   load_forecast  : 对未来的推测（会反复重算）
 *
 * 表结构定义在 db/02_forecast.sql。
 */
@Entity
@Table(name = "load_forecast")
public class LoadForecast {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id")
    private Long id;

    @Column(name = "region_code", nullable = false, length = 32)
    private String regionCode;

    @Column(name = "region_name", nullable = false, length = 64)
    private String regionName;

    /** 被预测的目标时刻 */
    @Column(name = "forecast_ts", nullable = false)
    private LocalDateTime forecastTs;

    @Column(name = "predicted_load", nullable = false, precision = 12, scale = 3)
    private BigDecimal predictedLoad;

    /** 喂给模型的输入，存下来是为了可追溯 */
    @Column(name = "input_temp", precision = 5, scale = 2)
    private BigDecimal inputTemp;

    @Column(name = "input_hour")
    private Integer inputHour;

    @Column(name = "model_name", nullable = false, length = 64)
    private String modelName;

    /** 训练时的 R²，前端可以用它提示"可信度" */
    @Column(name = "model_r2", precision = 6, scale = 4)
    private BigDecimal modelR2;

    @Column(name = "create_time", insertable = false, updatable = false)
    private LocalDateTime createTime;

    public LoadForecast() {
    }

    public Long getId() {
        return id;
    }

    public void setId(Long id) {
        this.id = id;
    }

    public String getRegionCode() {
        return regionCode;
    }

    public void setRegionCode(String regionCode) {
        this.regionCode = regionCode;
    }

    public String getRegionName() {
        return regionName;
    }

    public void setRegionName(String regionName) {
        this.regionName = regionName;
    }

    public LocalDateTime getForecastTs() {
        return forecastTs;
    }

    public void setForecastTs(LocalDateTime forecastTs) {
        this.forecastTs = forecastTs;
    }

    public BigDecimal getPredictedLoad() {
        return predictedLoad;
    }

    public void setPredictedLoad(BigDecimal predictedLoad) {
        this.predictedLoad = predictedLoad;
    }

    public BigDecimal getInputTemp() {
        return inputTemp;
    }

    public void setInputTemp(BigDecimal inputTemp) {
        this.inputTemp = inputTemp;
    }

    public Integer getInputHour() {
        return inputHour;
    }

    public void setInputHour(Integer inputHour) {
        this.inputHour = inputHour;
    }

    public String getModelName() {
        return modelName;
    }

    public void setModelName(String modelName) {
        this.modelName = modelName;
    }

    public BigDecimal getModelR2() {
        return modelR2;
    }

    public void setModelR2(BigDecimal modelR2) {
        this.modelR2 = modelR2;
    }

    public LocalDateTime getCreateTime() {
        return createTime;
    }

    public void setCreateTime(LocalDateTime createTime) {
        this.createTime = createTime;
    }
}
