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
 * 第 4 步 · 实体类（Entity）—— ORM 的"翻译字典"
 *
 * 这个类的作用只有一个：告诉 JPA
 *      "Java 的这个类   <->   数据库的这张表"
 *      "类的这个字段     <->   表的这一列"
 *
 * 类名 LoadRecord   ->  自动对应表 load_record（驼峰转下划线）
 * 但下面还是写了 @Table(name = "load_record")，因为显式写出来更好读、
 * 以后表名改名也不会"魔法失效"。
 */
@Entity
@Table(name = "load_record")
public class LoadRecord {

    /**
     * 主键。
     *   @Id                          -> 这一列是主键
     *   @GeneratedValue(IDENTITY)    -> 主键由数据库自增产生（对应 MySQL 的 AUTO_INCREMENT）
     *                                   IDENTITY 的意思是"交给数据库生成"，
     *                                   插入时 Java 不用管 id，数据库自己 +1
     */
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    @Column(name = "id")
    private Long id;

    /** 地区编码，如 GD-01 */
    @Column(name = "region_code", nullable = false, length = 32)
    private String regionCode;

    /** 地区名称，如 广州 */
    @Column(name = "region_name", nullable = false, length = 64)
    private String regionName;

    /**
     * 采样时刻。
     * 数据库是 DATETIME，Java 用 LocalDateTime 对应（java.time 包，JDK 8+ 的现代写法）。
     */
    @Column(name = "ts", nullable = false)
    private LocalDateTime ts;

    /**
     * 负荷值(kW)。
     *
     * 为什么用 BigDecimal 而不是 double？
     *   double 是二进制浮点数，算 0.1 + 0.2 会得到 0.30000000000000004。
     *   电力负荷、金额这类"不能有误差"的数字，必须用 BigDecimal（十进制精确计算）。
     *   数据库那列也是 DECIMAL(12,3)，两边正好对上。
     *   —— 这一条是面试加分项：能说清 double 和 BigDecimal 的区别。
     */
    @Column(name = "load_kw", nullable = false, precision = 12, scale = 3)
    private BigDecimal loadKw;

    /** 气温(℃)，数据库允许为 NULL，所以这里用包装类型 Double / BigDecimal，不能用 double */
    @Column(name = "temperature", precision = 5, scale = 2)
    private BigDecimal temperature;

    /** 1 = 算法判定为异常点。TINYINT(1) 在 Java 里用 Integer 或 Boolean 都行，这里用 Integer 更直白 */
    @Column(name = "is_anomaly", nullable = false)
    private Integer isAnomaly;

    /**
     * 入库时间。
     * 数据库有 DEFAULT CURRENT_TIMESTAMP 自己填，所以这里声明
     *   insertable = false, updatable = false
     * 意思是"这一列我不负责写，让数据库自己管"。
     * 如果不禁掉，JPA 插入时会塞一个 null 进去，覆盖掉数据库默认值。
     */
    @Column(name = "create_time", insertable = false, updatable = false)
    private LocalDateTime createTime;

    // ============================================================
    //  JPA 要求实体类必须有一个"无参构造器"。
    //  你不写任何构造器时 Java 会自动送一个，但你一旦自己写了带参构造器，
    //  这个默认的就没了 —— 所以这里显式写出来，避免以后踩坑。
    // ============================================================
    public LoadRecord() {
    }

    // ============================================================
    //  getter / setter
    //  Spring 转 JSON 时靠 getter 读值：getRegionName() -> "regionName" 字段
    //  JPA 从数据库读数据时靠 setter 写值
    //  两者缺一个，字段就会在 JSON 里消失或者读不出来
    // ============================================================

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

    public LocalDateTime getTs() {
        return ts;
    }

    public void setTs(LocalDateTime ts) {
        this.ts = ts;
    }

    public BigDecimal getLoadKw() {
        return loadKw;
    }

    public void setLoadKw(BigDecimal loadKw) {
        this.loadKw = loadKw;
    }

    public BigDecimal getTemperature() {
        return temperature;
    }

    public void setTemperature(BigDecimal temperature) {
        this.temperature = temperature;
    }

    public Integer getIsAnomaly() {
        return isAnomaly;
    }

    public void setIsAnomaly(Integer isAnomaly) {
        this.isAnomaly = isAnomaly;
    }

    public LocalDateTime getCreateTime() {
        return createTime;
    }

    public void setCreateTime(LocalDateTime createTime) {
        this.createTime = createTime;
    }
}
