package com.example.powerload.dto;

import java.math.BigDecimal;

/**
 * 第 5 步 · DTO（Data Transfer Object）—— 专门装"聚合查询结果"的小盒子
 *
 * 为什么需要它？
 *   聚合查询的结果（平均负荷、峰值…）在数据库里是"现算出来的"，
 *   原表 load_record 里没有这些列，实体类 LoadRecord 里自然也没有这些字段。
 *   所以不能用 List<LoadRecord> 来接，必须另建一个类来装。
 *
 * 它和实体类的区别（面试可以这么说）：
 *   Entity(LoadRecord)     = 对应数据库里一张真实的表，一个对象 = 一行
 *   DTO(RegionSummaryDTO)  = 不对应任何表，只对应"这次接口要返回的数据形状"
 *
 * 为什么不直接返回 List<Object[]>（网上很多教程这么写）？
 *   那样调用方得写 row[0]、row[1]……没人知道下标 3 是什么，改一次查询就全崩。
 *   用 DTO 之后：字段有名字、有类型，编译器帮你把关，IDE 还能自动补全。
 *
 * ★ 关键：JPQL 里的 "select new com.example.powerload.dto.RegionSummaryDTO(...)"
 *   要求这个类必须有一个"参数顺序、参数类型都完全对应"的构造器。
 *
 *   下面这些类型不是随便写的，是"实测"出来的 —— Hibernate 6 对聚合函数的
 *   返回类型有它自己的一套推断规则：
 *
 *      COUNT(...)           -> java.lang.Long
 *      SUM(整数列)           -> java.lang.Long
 *      AVG(...)             -> java.lang.Double   ← 唯一返回 Double 的那个！
 *      MAX/MIN(小数列)       -> java.math.BigDecimal
 *
 *   ★ 坑点：AVG 返回的是 Double，不是 BigDecimal。
 *     如果按直觉写成 BigDecimal，应用启动会直接失败，报：
 *        org.hibernate.query.SemanticException: Missing constructor for type 'RegionSummaryDTO'
 *     翻译过来是："我找不到一个参数类型能对上的构造器"。
 *     —— 这个坑第一次用 DTO 投影的人几乎都会踩，记住它。
 *
 *   那字段为什么还留 BigDecimal？
 *   因为 Double 做负荷/金额这类计算会有精度误差。所以构造器收 Double（迁就
 *   Hibernate），但立刻转成 BigDecimal 存下来（保护业务精度）。
 *   这叫"在边界处做类型转换"，面试可以聊这个思路。
 */
public class RegionSummaryDTO {

    private String regionCode;
    private String regionName;
    private Long sampleCount;      // COUNT(*) 在 Java 里是 Long
    private BigDecimal avgLoad;    // 存成 BigDecimal，防止 Double 精度问题
    private BigDecimal maxLoad;
    private BigDecimal minLoad;
    private Long anomalyCount;     // SUM(is_anomaly) 的结果也是 Long

    public RegionSummaryDTO(String regionCode,
                            String regionName,
                            Long sampleCount,
                            Double avgLoad,        // ← Hibernate 给的是 Double，不能写 BigDecimal
                            BigDecimal maxLoad,
                            BigDecimal minLoad,
                            Long anomalyCount) {
        this.regionCode = regionCode;
        this.regionName = regionName;
        this.sampleCount = sampleCount;
        // Double -> BigDecimal：先转字符串再构造，避免把 Double 自带的二进制误差带进来
        this.avgLoad = (avgLoad == null) ? null : new BigDecimal(avgLoad.toString());
        this.maxLoad = maxLoad;
        this.minLoad = minLoad;
        this.anomalyCount = anomalyCount;
    }

    // getter —— Spring 靠它们把字段转成 JSON。
    // 没有 setter 是故意的：这个盒子只读，建好之后不该被改。
    public String getRegionCode() {
        return regionCode;
    }

    public String getRegionName() {
        return regionName;
    }

    public Long getSampleCount() {
        return sampleCount;
    }

    public BigDecimal getAvgLoad() {
        return avgLoad;
    }

    public BigDecimal getMaxLoad() {
        return maxLoad;
    }

    public BigDecimal getMinLoad() {
        return minLoad;
    }

    public Long getAnomalyCount() {
        return anomalyCount;
    }
}
