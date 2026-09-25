package com.example.powerload.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.time.LocalDateTime;

/**
 * 第 5 步 · 实体类 —— 对应表 load_daily_stat（日统计结果表）
 *
 * 和 LoadRecord（明细表）的区别：
 *   LoadRecord     一次采样一行，数据量大
 *   LoadDailyStat  一个地区一天一行，数据量小，但每行都是"算出来的"
 *
 * 这张表以后由 Python 的负荷预测脚本写回，
 * 也是"统计接口"最主要的数据来源。
 *
 * 顺带看一个新类型：
 *   stat_date 是 DATE 类型 -> Java 用 LocalDate（只有年月日，没有时分秒）
 *   create_time 是 DATETIME -> Java 用 LocalDateTime（有年月日时分秒）
 *   这两个别混用：用 LocalDateTime 去接 DATE 列，虽然能跑，但语义是错的。
 */
@Entity
@Table(name = "load_daily_stat")
public class LoadDailyStat {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id")
    private Long id;

    @Column(name = "region_code", nullable = false, length = 32)
    private String regionCode;

    @Column(name = "stat_date", nullable = false)
    private LocalDate statDate;

    @Column(name = "avg_load", nullable = false, precision = 12, scale = 3)
    private BigDecimal avgLoad;

    @Column(name = "max_load", nullable = false, precision = 12, scale = 3)
    private BigDecimal maxLoad;

    @Column(name = "min_load", nullable = false, precision = 12, scale = 3)
    private BigDecimal minLoad;

    @Column(name = "anomaly_cnt", nullable = false)
    private Integer anomalyCnt;

    @Column(name = "create_time", insertable = false, updatable = false)
    private LocalDateTime createTime;

    /** JPA 需要无参构造器 */
    public LoadDailyStat() {
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

    public LocalDate getStatDate() {
        return statDate;
    }

    public void setStatDate(LocalDate statDate) {
        this.statDate = statDate;
    }

    public BigDecimal getAvgLoad() {
        return avgLoad;
    }

    public void setAvgLoad(BigDecimal avgLoad) {
        this.avgLoad = avgLoad;
    }

    public BigDecimal getMaxLoad() {
        return maxLoad;
    }

    public void setMaxLoad(BigDecimal maxLoad) {
        this.maxLoad = maxLoad;
    }

    public BigDecimal getMinLoad() {
        return minLoad;
    }

    public void setMinLoad(BigDecimal minLoad) {
        this.minLoad = minLoad;
    }

    public Integer getAnomalyCnt() {
        return anomalyCnt;
    }

    public void setAnomalyCnt(Integer anomalyCnt) {
        this.anomalyCnt = anomalyCnt;
    }

    public LocalDateTime getCreateTime() {
        return createTime;
    }

    public void setCreateTime(LocalDateTime createTime) {
        this.createTime = createTime;
    }
}
