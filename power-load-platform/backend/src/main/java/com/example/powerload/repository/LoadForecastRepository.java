package com.example.powerload.repository;

import com.example.powerload.entity.LoadForecast;
import org.springframework.data.jpa.repository.JpaRepository;

import java.time.LocalDateTime;
import java.util.List;

/**
 * 第 7 步 · 预测结果的仓库
 *
 * 这里的方法全部用"派生查询"（方法名即 SQL）就够了 ——
 * 因为预测数据的查询需求很朴素：按地区取、按时间排序、取最新一批。
 * 不需要写 JPQL。
 *
 * 顺便体会一下第 4 步讲过的"方法名即 SQL"在这里有多省事：
 *   findByRegionCodeOrderByForecastTsAsc
 *     -> SELECT * FROM load_forecast WHERE region_code = ? ORDER BY forecast_ts ASC
 */
public interface LoadForecastRepository extends JpaRepository<LoadForecast, Long> {

    /** 某地区的预测曲线，按时间正序（前端画折线图直接用这个顺序） */
    List<LoadForecast> findByRegionCodeOrderByForecastTsAsc(String regionCode);

    /** 全部地区的预测，按地区 + 时间排序 */
    List<LoadForecast> findAllByOrderByRegionCodeAscForecastTsAsc();

    /** 从某个时刻开始的预测（比如"只看今天剩下的"） */
    List<LoadForecast> findByForecastTsAfterOrderByForecastTsAsc(LocalDateTime from);

    /** 某个地区、某个时间段内的预测 */
    List<LoadForecast> findByRegionCodeAndForecastTsBetweenOrderByForecastTsAsc(
            String regionCode, LocalDateTime from, LocalDateTime to);

    // 注意：这里不需要写 count()。
    // JpaRepository 里已经白送了一个 count()，
    // 再声明一遍属于重复定义 —— 新手常犯，会让代码看起来"不懂父类有什么"。
}
