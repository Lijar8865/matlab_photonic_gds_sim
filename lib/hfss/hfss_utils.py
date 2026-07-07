# -*- coding: utf-8 -*-
"""
HFSS IronPython 工具函数库
兼容 IronPython 2.7 (HFSS 2025.1)
"""

import os


def create_sweep_polyline(oEditor, points, Str_name, Material, SweepVector, solve_inside=True):
    """
    在HFSS中创建多段线并拉伸，赋予材料属性
    
    参数:
        oEditor: HFSS 3D Modeler 编辑器对象
        points: 坐标点列表 [(x1,y1), (x2,y2), ...]，单位 nm
        Str_name: 结构名称
        Material: 材料名称
        SweepVector: 拉伸向量 (x, y, z)，如 ("0um", "0um", "H_Au")
        solve_inside: 是否对该实体开启 Solve Inside，默认 True
    """
    polyline_points = []
    for x, y in points:
        point = [
            "NAME:PLPoint",
            "X:=", "{0}nm".format(x),
            "Y:=", "{0}nm".format(y),
            "Z:=", "H_slab+H_clad"
        ]
        polyline_points.append(point)

    segments = []
    for i in range(len(points)-1):
        segment = [
            "NAME:PLSegment",
            "SegmentType:=", "Line",
            "StartIndex:=", i,
            "NoOfPoints:=", 2
        ]
        segments.append(segment)

    oEditor.CreatePolyline(
        [
            "NAME:PolylineParameters",
            "IsPolylineCovered:=", True,
            "IsPolylineClosed:=", True,
            [
                "NAME:PolylinePoints"
            ] + polyline_points,
            [
                "NAME:PolylineSegments"
            ] + segments,
            [
                "NAME:PolylineXSection",
                "XSectionType:=", "None",
                "XSectionOrient:=", "Auto",
                "XSectionWidth:=", "0nm",
                "XSectionTopWidth:=", "0nm",
                "XSectionHeight:=", "0nm",
                "XSectionNumSegments:=", "0",
                "XSectionBendType:=", "Corner"
            ]
        ],
        [
            "NAME:Attributes",
            "Name:=", Str_name,
            "Flags:=", "",
            "Color:=", "(255 215 0)",
            "Transparency:=", 0,
            "PartCoordinateSystem:=", "Global",
            "MaterialValue:=", '"{0}"'.format(Material),
            "SurfaceMaterialValue:=", '""',
            "SolveInside:=", solve_inside,
            "ShellElement:=", False
        ])

    oEditor.SweepAlongVector(
        [
            "NAME:Selections",
            "Selections:=", Str_name,
            "NewPartsModelFlag:=", "Model"
        ],
        [
            "NAME:VectorSweepParameters",
            "DraftAngle:=", "0deg",
            "DraftType:=", "Round",
            "CheckFaceFaceIntersection:=", False,
            "ClearAllIDs:=", False,
            "SweepVectorX:=", SweepVector[0],
            "SweepVectorY:=", SweepVector[1],
            "SweepVectorZ:=", SweepVector[2]
        ])

    oEditor.AssignMaterial(
        [
            "NAME:Selections",
            "AllowRegionDependentPartSelectionForPMLCreation:=", True,
            "AllowRegionSelectionForPMLCreation:=", True,
            "Selections:=", Str_name
        ],
        [
            "NAME:Attributes",
            "MaterialValue:=", '"{0}"'.format(Material),
            "SolveInside:=", solve_inside,
            "ShellElement:=", False,
            "ShellElementThickness:=", "nan ",
            "ReferenceTemperature:=", "nan ",
            "IsMaterialEditable:=", True,
            "IsSurfaceMaterialEditable:=", True,
            "UseMaterialAppearance:=", False,
            "IsLightweight:=", False
        ])


def change_local_variable(oDesign, Para_Name, Para_value):
    """
    修改 HFSS 设计中的局部变量
    
    参数:
        oDesign: HFSS Design 对象
        Para_Name: 参数名称
        Para_value: 参数值（字符串，如 "10um"）
    """
    oDesign.ChangeProperty(
        [
            "NAME:AllTabs",
            [
                "NAME:LocalVariableTab",
                [
                    "NAME:PropServers",
                    "LocalVariables"
                ],
                [
                    "NAME:ChangedProps",
                    [
                        "NAME:" + Para_Name,
                        "Value:=", Para_value
                    ]
                ]
            ]
        ]
    )


def change_object_material(oEditor, object_name, material_name):
    """
    修改指定几何体的材料属性
    
    参数:
        oEditor: HFSS 3D Modeler 编辑器对象
        object_name: 对象名称
        material_name: 材料名称
    """
    oEditor.ChangeProperty(
        [
            "NAME:AllTabs",
            [
                "NAME:Geometry3DAttributeTab",
                [
                    "NAME:PropServers",
                    object_name
                ],
                [
                    "NAME:ChangedProps",
                    [
                        "NAME:Material",
                        "Value:=", '"{0}"'.format(material_name)
                    ]
                ]
            ]
        ]
    )


def change_rectangle_position(oEditor, rect_name, x_expr, y_expr, z_expr, create_index=1):
    """
    修改矩形对象的位置
    
    参数:
        oEditor: HFSS 3D Modeler 编辑器对象
        rect_name: 矩形名称
        x_expr: X 坐标表达式
        y_expr: Y 坐标表达式
        z_expr: Z 坐标表达式
        create_index: 创建索引，默认 1
    """
    prop_server = "{0}:CreateRectangle:{1}".format(rect_name, create_index)
    oEditor.ChangeProperty(
        [
            "NAME:AllTabs",
            [
                "NAME:Geometry3DCmdTab",
                [
                    "NAME:PropServers",
                    prop_server
                ],
                [
                    "NAME:ChangedProps",
                    [
                        "NAME:Position",
                        "X:=", x_expr,
                        "Y:=", y_expr,
                        "Z:=", z_expr
                    ]
                ]
            ]
        ]
    )


def change_rectangle_axis(oEditor, rect_name, axis_value="X", create_index=1):
    """
    修改矩形对象的轴向
    
    参数:
        oEditor: HFSS 3D Modeler 编辑器对象
        rect_name: 矩形名称
        axis_value: 轴向值，如 "X", "Y", "Z"
        create_index: 创建索引，默认 1
    """
    prop_server = "{0}:CreateRectangle:{1}".format(rect_name, create_index)
    oEditor.ChangeProperty(
        [
            "NAME:AllTabs",
            [
                "NAME:Geometry3DCmdTab",
                [
                    "NAME:PropServers",
                    prop_server
                ],
                [
                    "NAME:ChangedProps",
                    [
                        "NAME:Axis",
                        "Value:=", axis_value
                    ]
                ]
            ]
        ]
    )


def assign_terminal(oDesign, terminal_name, edge_ids, parent_bnd_id, impedance="50ohm"):
    """
    在HFSS中分配端口终端
    
    参数:
        oDesign: HFSS Design 对象
        terminal_name: 终端名称，如 "S1_T1"
        edge_ids: 边ID列表，如 [622] 或 [622, 623]
        parent_bnd_id: 父边界ID字符串，如 "1"
        impedance: 终端阻抗，默认 "50ohm"
    """
    oModule = oDesign.GetModule("BoundarySetup")
    oModule.AssignTerminal(
        [
            "NAME:" + terminal_name,
            "Edges:=", edge_ids,
            "ParentBndID:=", parent_bnd_id,
            "ImpedanceType:=", "Impedance",
            "TerminalResistance:=", impedance
        ]
    )


def export_report_to_csv(oModule, Para, save_dir):
    """
    导出HFSS报告为CSV文件
    
    参数:
        oModule: ReportSetup 模块对象
        Para: 报告名称字符串，如 "S11"
        save_dir: 保存目录（建议用绝对路径）
    """
    oModule.UpdateReports([Para])
    oModule.ExportToFile(Para, os.path.join(save_dir, Para + ".csv"), False)


def export_network_data(oDesign, filename, save_dir):
    """
    导出HFSS网络数据为.tab文件（自动构建 VariationString）
    
    参数:
        oDesign: HFSS Design 对象
        filename: 输出文件名（不含扩展名），如 "HFSS_matrix"
        save_dir: 保存目录（建议用绝对路径）
    """
    # 获取所有LocalVariables的属性名并构建VariationString
    property_names = oDesign.GetProperties('LocalVariableTab', 'LocalVariables')
    variation_parts = []
    for prop_name in property_names:
        prop_value = oDesign.GetPropertyValue('LocalVariableTab', 'LocalVariables', prop_name)
        variation_parts.append("{0}='{1}'".format(prop_name, prop_value))
    
    variation_string = " ".join(variation_parts)
    print("Variation String: {0}".format(variation_string))
    
    oModule = oDesign.GetModule("Solutions")
    output_path = os.path.join(save_dir, filename + ".tab")
    
    oModule.ExportNetworkData(
        variation_string,
        ["Setup1:Freq_Sweep"],
        2,
        output_path,
        "all",
        False,
        50,
        ["S", "Zo", "Gamma"],
        -1,
        0,
        15,
        True,
        True,
        False
    )
    print("Network data exported to: {0}".format(output_path))


class DotObject(object):
    """
    将字典转换为支持点号访问的对象
    用法: data = DotObject(json_dict)
    """
    def __init__(self, mapping):
        for key, value in mapping.items():
            setattr(self, key, self._convert(value))

    def _convert(self, value):
        if isinstance(value, dict):
            return DotObject(value)
        if isinstance(value, list):
            return [self._convert(item) for item in value]
        return value


def get_points_from_data(data):
    """
    从数据对象中提取坐标点
    
    参数:
        data: DotObject 对象
    
    返回:
        坐标点列表 [(x1,y1), (x2,y2), ...]，单位 nm
    """
    # 直接按 nm 读取 sim_struct（N x 2）
    if hasattr(data, 'sim_struct') and isinstance(data.sim_struct, list):
        pts = []
        for row in data.sim_struct:
            if (isinstance(row, list) or isinstance(row, tuple)) and len(row) >= 2:
                try:
                    xv = float(row[0])
                    yv = float(row[1])
                    pts.append((xv, yv))
                except:
                    pass
        return pts

    # 回退：老格式 x/y（一维向量，假定已为 nm）
    if hasattr(data, 'x') and hasattr(data, 'y'):
        try:
            return [(float(x), float(y)) for x, y in zip(data.x, data.y)]
        except:
            return list(zip(data.x, data.y))

    return []


def debug_sim_struct(data, max_rows=5):
    """
    调试打印 sim_struct 数据结构
    
    参数:
        data: DotObject 对象
        max_rows: 打印的最大行数
    """
    try:
        has_ss = hasattr(data, 'sim_struct')
        print("has sim_struct:", has_ss)
        if not has_ss:
            return
        ss = data.sim_struct
        print("sim_struct type:", type(ss).__name__)
        try:
            print("sim_struct len:", len(ss))
        except:
            pass
        if isinstance(ss, list) and len(ss) > 0:
            print("row0 type:", type(ss[0]).__name__)
            if isinstance(ss[0], (list, tuple)) and len(ss[0]) >= 2:
                print("row0 elem types:", type(ss[0][0]).__name__, type(ss[0][1]).__name__)
            # 打印前几行样例
            n = min(max_rows, len(ss))
            for i in range(n):
                try:
                    print("row{0}: {1}, {2}".format(i, ss[i][0], ss[i][1]))
                except:
                    print("row{0}: <print error>".format(i))
    except Exception as e:
        print("debug_sim_struct error:", e)