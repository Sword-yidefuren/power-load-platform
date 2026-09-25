package com.example.powerload.repository;

import com.example.powerload.dto.RegionSummaryDTO;
import com.example.powerload.entity.LoadDailyStat;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;

import java.util.List;

/**
 * 第 5 步 · 日统计表的仓库
 *
 * load_daily_stat 这张表是"聚合结果表"：
 * 它的一行 = 某地区某一天的平均/峰值/谷值/异常数。
 * 以后 Python 的负荷预测会把结果写回这张表，统计接口从这里读。
 *
 * 注意它和 LoadRecordRepository 的分工：
 *   load_record     -> 明细（每次采样一行，量很大）
 *   load_daily_stat -> 汇总（每地区每天一行，量很小）
 * 这是数据仓库里典型的"事实表 + 汇总表"设计，面试聊项目时值得提。
 */
public interface LoadDailyStatRepository extends JpaRepository<LoadDailyStat, Long> {

    /** 按地区编码查，按日期正序 */
    List<LoadDailyStat> findByRegionCodeOrderByStatDateAsc(String regionCode);

    /**
     * ★ 本步重点：把"聚合查询"的结果直接装进 DTO
     *
     * 注意这不是 SQL，是 JPQL（Java Persistence Query Language）——
     * 它操作的是"实体类名和字段名"，不是表名和列名：
     *
     *      SQL  写法 :  SELECT region_name ... FROM load_record    GROUP BY region_name
     *      JPQL 写法 :  SELECT r.regionName ... FROM LoadRecord r  GROUP BY r.regionName
     *                     └─┬─┘              └───┬────┘   └┬┘
     *                   Java 字段名          实体类名    别名
     *
     * 好处：查询跟着实体类走。哪天数据库把列改名成 region，只要改实体类的
     * @Column 映射，这条 JPQL 一个字都不用动。用原生 SQL 就得满项目找。
     *
     * "select new 包名.类名(...)" 这段是 JPQL 的"构造器表达式"(constructor
     * expression)，它会 new 出 RegionSummaryDTO 对象，把查询结果按顺序塞进去。
     *
     * ⚠️ 极其重要：构造器的参数类型必须和 Hibernate 推断出来的类型"完全一致"。
     *    实测结果（写错一个启动直接失败）：
     *      COUNT(r)        -> Long
     *      AVG(r.loadKw)   -> Double      ← 最容易写错的一个
     *      MAX(r.loadKw)   -> BigDecimal
     *      MIN(r.loadKw)   -> BigDecimal
     *      SUM(r.isAnomaly)-> Long
     */
    @Query("SELECT new com.example.powerload.dto.RegionSummaryDTO(" +
           "  r.regionCode, r.regionName, COUNT(r), " +
           "  AVG(r.loadKw), MAX(r.loadKw), MIN(r.loadKw), SUM(r.isAnomaly)) " +
           "FROM LoadRecord r " +
           "GROUP BY r.regionCode, r.regionName " +
           "ORDER BY AVG(r.loadKw) DESC")
    List<RegionSummaryDTO> summarizeByRegion();
}
