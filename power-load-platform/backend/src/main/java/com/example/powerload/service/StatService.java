package com.example.powerload.service;

import com.example.powerload.dto.RegionSummaryDTO;
import com.example.powerload.entity.LoadDailyStat;
import com.example.powerload.repository.LoadDailyStatRepository;
import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 第 5 步 · 统计服务 —— 聚合查询都放这里
 *
 * 这一层开始有"真正的业务逻辑"了（不是简单的转发）：
 *   - 把聚合结果做四舍五入
 *   - 计算"峰谷差"这种业务指标
 *   - 判断哪些地区的负荷波动异常
 * 这些都是"计算"，既不属于接请求，也不属于读写数据库，
 * 所以必须放在 Service —— 这正是 Service 层存在的理由。
 */
@Service
public class StatService {

    private final LoadDailyStatRepository dailyStatRepository;

    /**
     * EntityManager 是 JPA 的"总管家"，可以直接执行 JPQL。
     * 这里用它来跑一个"按日期聚合"的查询，演示 Repository + @Query 之外的第二条路。
     *
     * @PersistenceContext 是 Spring 给 EntityManager 的专用注入注解
     * （EntityManager 是"每个请求一份"的，不能像普通 Bean 那样共享，
     *   所以有它自己专门的注解）。
     */
    @PersistenceContext
    private EntityManager entityManager;

    public StatService(LoadDailyStatRepository dailyStatRepository) {
        this.dailyStatRepository = dailyStatRepository;
    }

    /**
     * 按地区聚合 —— 读的是 load_daily_stat（已经算好的统计表）
     */
    @Transactional(readOnly = true)
    public List<LoadDailyStat> dailyStatAll() {
        return dailyStatRepository.findAll();
    }

    @Transactional(readOnly = true)
    public List<LoadDailyStat> dailyStatByRegion(String regionCode) {
        String code = (regionCode == null || regionCode.isBlank()) ? "GD-01" : regionCode.trim();
        return dailyStatRepository.findByRegionCodeOrderByStatDateAsc(code);
    }

    /**
     * ★ 核心：按地区做聚合统计，结果装进 DTO
     *
     * 数据来源是 load_record（明细表）而不是 load_daily_stat，
     * 因为它们回答的问题不同：
     *   load_daily_stat -> "算法算好的结论"
     *   这里的 GROUP BY -> "现在实时算一遍"（能拿到最新数据，不依赖算法跑没跑）
     *
     * SQL 对应关系（你在 MySQL 里手写过的那句）：
     *   SELECT region_name, COUNT(*), AVG(load_kw), MAX(load_kw), MIN(load_kw), SUM(is_anomaly)
     *   FROM load_record GROUP BY region_name ORDER BY AVG(load_kw) DESC
     */
    @Transactional(readOnly = true)
    public List<RegionSummaryDTO> summarizeByRegion() {
        return dailyStatRepository.summarizeByRegion();
    }

    /**
     * 业务加工：把聚合结果里派生出新指标。
     *
     * 这里算的是电力行业常用的"峰谷差"和"负荷率"：
     *   峰谷差 = 最高负荷 - 最低负荷     （差值越大，说明用电越不均衡，对电网压力越大）
     *   负荷率 = 平均负荷 / 最高负荷     （越接近 1 说明用电越平稳，是电网最喜欢的）
     *
     * 注意：这两个指标在数据库里都没有，
     * 是 Java 算出来的 —— 这就是"业务逻辑必须有一层专门放"的最好例子。
     */
    @Transactional(readOnly = true)
    public List<Map<String, Object>> regionSummaryWithDerived() {
        List<RegionSummaryDTO> raw = summarizeByRegion();
        List<Map<String, Object>> out = new ArrayList<>();

        for (RegionSummaryDTO d : raw) {
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("regionCode", d.getRegionCode());
            row.put("regionName", d.getRegionName());
            row.put("sampleCount", d.getSampleCount());
            row.put("avgLoad", d.getAvgLoad());
            row.put("maxLoad", d.getMaxLoad());
            row.put("minLoad", d.getMinLoad());
            row.put("anomalyCount", d.getAnomalyCount());

            // 派生指标：峰谷差
            BigDecimal peakValleyDiff = d.getMaxLoad().subtract(d.getMinLoad());
            row.put("peakValleyDiff", peakValleyDiff);

            // 派生指标：负荷率（保留 4 位小数，除以 0 要防）
            BigDecimal loadRate = BigDecimal.ZERO;
            if (d.getMaxLoad() != null && d.getMaxLoad().signum() > 0) {
                loadRate = d.getAvgLoad()
                        .divide(d.getMaxLoad(), 4, RoundingMode.HALF_UP);
            }
            row.put("loadRate", loadRate);

            out.add(row);
        }
        return out;
    }

    /**
     * 按日期聚合 —— 用 EntityManager 直接跑 JPQL（另一条路，对比用）
     *
     * 返回结构手工拼成"日期 -> 统计"的列表，
     * 因为 Object[] 直接转 JSON 会变成 [[...],[...]] 这种没字段名的数组，
     * 前端根本没法用（这正是 DTO 存在的理由，你马上能亲眼看到差别）。
     */
    @Transactional(readOnly = true)
    public List<Map<String, Object>> summarizeByDate() {
        List<Object[]> rows = entityManager.createQuery(
                "SELECT FUNCTION('DATE', r.ts), COUNT(r), AVG(r.loadKw), MAX(r.loadKw) " +
                "FROM LoadRecord r " +
                "GROUP BY FUNCTION('DATE', r.ts) " +
                "ORDER BY FUNCTION('DATE', r.ts) ASC",
                Object[].class).getResultList();

        List<Map<String, Object>> out = new ArrayList<>();
        for (Object[] r : rows) {
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("statDate", String.valueOf(r[0]));
            row.put("sampleCount", r[1]);
            row.put("avgLoad", r[2]);
            row.put("maxLoad", r[3]);
            out.add(row);
        }
        return out;
    }
}
