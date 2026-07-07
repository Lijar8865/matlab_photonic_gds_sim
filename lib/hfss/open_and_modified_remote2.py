# -*- coding: utf-8 -*-
# ----------------------------------------------
# Script Recorded by Ansys Electronics Desktop Version 2025.1.0
import ScriptEnv
import os
import json
# define function
################################################################################################################


def create_sweep_polyline(oEditor, points, Str_name, Material, SweepVector, solve_inside=True):
    # 在HFSS中创建多段线并拉伸，赋予材料属性。
    # solve_inside: 是否对该实体开启 Solve Inside，默认 True
    polyline_points = []
    for x, y in points:
        point = [
            "NAME:PLPoint",
            "X:=", "{}nm".format(x),
            "Y:=", "{}nm".format(y),
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
            "MaterialValue:=", "\"{}\"".format(Material),
            "SurfaceMaterialValue:=", "\"\"",
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
            "MaterialValue:=", "\"{}\"".format(Material),
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
    # 修改指定几何体的材料属性
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
                        "Value:=", "\"" + material_name + "\""
                    ]
                ]
            ]
        ]
    )

# ...existing code...

def change_rectangle_position(oEditor, rect_name, x_expr, y_expr, z_expr, create_index=1):
    # IronPython 2.7 不支持 f-string
    prop_server = "{}:CreateRectangle:{}".format(rect_name, create_index)
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
    prop_server = "{}:CreateRectangle:{}".format(rect_name, create_index)
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
    # """
    # 在HFSS中分配端口终端
    
    # 参数:
    #     oDesign: HFSS设计对象
    #     terminal_name: 终端名称，如 "S1_T1"
    #     edge_ids: 边ID列表，如 [622] 或 [622, 623]
    #     parent_bnd_id: 父边界ID字符串，如 "1"
    #     impedance: 终端阻抗，默认 "50ohm"
    # """
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


class DotObject(object):
    def __init__(self, mapping):
        for key, value in mapping.items():
            setattr(self, key, self._convert(value))

    def _convert(self, value):
        if isinstance(value, dict):
            return DotObject(value)
        if isinstance(value, list):
            return [self._convert(item) for item in value]
        return value


# 导出HFSS报告为CSV文件的函数
def export_report_to_csv(oModule, Para, save_dir):
    # oModule: ReportSetup模块对象
    # Para: 报告名称字符串，如"S11mag"
    # save_dir: 保存目录（建议用绝对路径）
    oModule.UpdateReports([Para])
    oModule.ExportToFile(Para, os.path.join(save_dir, Para + ".csv"), False)
def get_points_from_data(data):
    # 直接按 nm 读取 sim_struct（N x 2），不做单位转换
    if hasattr(data, 'sim_struct') and isinstance(data.sim_struct, list):
        pts = []
        for row in data.sim_struct:
            if (isinstance(row, list) or isinstance(row, tuple)) and len(row) >= 2:
                try:
                    # 转为 float，兼容 int/float
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
                    print("row{}: {}, {}".format(i, ss[i][0], ss[i][1]))
                except:
                    print("row{}: <print error>".format(i))
    except Exception as e:
        print("debug_sim_struct error:", e)
################################################################################################################


if __name__ == "__main__":
    current_dir = os.path.dirname(os.path.abspath(__file__))
    base_path = os.path.join(current_dir, "T_rail_TWE_GSG_base.aedt")
    ScriptEnv.Initialize("Ansoft.ElectronicsDesktop")
    oDesktop.RestoreWindow() 
    oDesktop.OpenProject(base_path)
    oProject = oDesktop.SetActiveProject("T_rail_TWE_GSG_base")
    oDesign = oProject.SetActiveDesign("HFSSDesign1")
    oEditor = oDesign.SetActiveEditor("3D Modeler")
    
    # csv_path = os.path.join(current_dir, 'arc_points.csv')
    json_path = os.path.join(current_dir, 'matlab_to_hfss.json')
    # Read JSON file
    with open(json_path, 'r') as f:
        raw_data = json.load(f)
    data = DotObject(raw_data)
    # points = list(zip(data.x, data.y))
        # 调试打印：查看 sim_struct 的类型与部分数据
    # debug_sim_struct(data, max_rows=3)
    # points = get_points_from_data(data)
    # points = data.sim_struct  # list[list[int]] 或 list[list[float]]
    save_folder = data.save_folder
    # save_name = "test_script_run"
    save_dir = os.path.join(current_dir, save_folder)
    if not os.path.isdir(save_dir):
        os.makedirs(save_dir)
    
    oProject = oDesktop.SetActiveProject("T_rail_TWE_GSG_base")
    save_path = os.path.join(save_dir,  "sim_result.aedt")
    oProject.SaveAs(save_path, True)
    oEditor.SetTopDownViewDirectionForActiveView("Global")
    oEditor.FitAll()
    # 改参数先
    change_local_variable(oDesign, "Gap", "{}um".format(data.Gap))
    change_local_variable(oDesign, "W_rail", "{}um".format(data.W_rail))
    change_local_variable(oDesign, "W_T", "{}um".format(data.W_T))
    change_local_variable(oDesign, "L_rail", "{}um".format(data.L_rail))
    change_local_variable(oDesign, "period", "{}um".format(data.period))
    change_local_variable(oDesign, "L_T", "{}um".format(data.L_T))
    change_local_variable(oDesign, "W_S", "{}um".format(data.W_S))
    change_local_variable(oDesign, "W_G", "{}um".format(data.W_G))
    change_local_variable(oDesign, "L", "{}um".format(data.L))
    change_local_variable(oDesign, "Li", "{}um".format(data.L*2))
    change_local_variable(oDesign, "N_ele", "{}".format(data.N_ele))
    change_local_variable(oDesign, "W", "720um")
    change_object_material(oEditor, "substrate", "silicon")
    oEditor.FitAll()
#加电极
    if data.T_flag==1:
        create_sweep_polyline(oEditor, data.T_rail_S_R, "T_rail_S_R", "gold", ("0um", "0um", "H_Au"), solve_inside=False)
        create_sweep_polyline(oEditor, data.T_rail_S_L, "T_rail_S_L", "gold", ("0um", "0um", "H_Au"), solve_inside=False)
        create_sweep_polyline(oEditor, data.T_rail_G_center, "T_rail_G_center", "gold", ("0um", "0um", "H_Au"), solve_inside=False)
        create_sweep_polyline(oEditor, data.T_rail_G_R, "T_rail_G_R", "gold", ("0um", "0um", "H_Au"), solve_inside=False)
        create_sweep_polyline(oEditor, data.T_rail_G_L, "T_rail_G_L", "gold", ("0um", "0um", "H_Au"), solve_inside=False)
#弯曲前的taper
    create_sweep_polyline(oEditor, data.G_taper_in, "G_taper_in", "gold", ("0um", "0um", "H_Au"), solve_inside=False)
    create_sweep_polyline(oEditor, data.G_taper_out, "G_taper_out", "gold", ("0um", "0um", "H_Au"), solve_inside=False)
    create_sweep_polyline(oEditor, data.G_taper_center, "G_taper_center", "gold", ("0um", "0um", "H_Au"), solve_inside=False)
#弯曲
    create_sweep_polyline(oEditor, data.Bend_G_ele, "Bend_G_ele", "gold", ("0um", "0um", "H_Au"), solve_inside=False)
    create_sweep_polyline(oEditor, data.Bend_S_ele, "Bend_S_ele", "gold", ("0um", "0um", "H_Au"), solve_inside=False)
    create_sweep_polyline(oEditor, data.Center_G_ele, "Center_G_ele", "gold", ("0um", "0um", "H_Au"), solve_inside=False)
#分配端口
    # assign_terminal(oDesign, "S1_T1", [622], "1")
    # assign_terminal(oDesign, "S2_T1", [634], "2")
#更改端口坐标
    change_rectangle_position(oEditor, "S1", "-W_S/2+{}um".format(data.Disp_S/2), "-L_lump", "H_slab+H_clad+H_Au", create_index=1)
    change_rectangle_position(oEditor, "S2", "-W_S/2-{}um".format(data.Disp_S/2), "-L_lump", "H_slab+H_clad+H_Au", create_index=1)
    change_rectangle_position(oEditor, "G1", "-W_G/2", "-L_lump", "H_slab+H_clad+H_Au", create_index=1)
    change_rectangle_position(oEditor, "G2", "-W_G/2+{}um".format(data.Disp_G/2), "-L_lump", "H_slab+H_clad+H_Au", create_index=1)
    change_rectangle_position(oEditor, "G3", "-W_G/2", "-2*L_lump", "H_slab+H_clad+H_Au", create_index=1)
    change_rectangle_position(oEditor, "G4", "-W_G/2", "-L_lump", "H_slab+H_clad+H_Au", create_index=1)
    change_rectangle_position(oEditor, "G5", "-W_G/2-{}um".format(data.Disp_G/2), "-L_lump", "H_slab+H_clad+H_Au", create_index=1)
    change_rectangle_position(oEditor, "G6", "-W_G/2-{}um".format(data.Disp_G/2), "-2*L_lump", "H_slab+H_clad+H_Au", create_index=1)

#更改setup
    oModule = oDesign.GetModule("AnalysisSetup")
    oModule.EditSetup("Setup1", 
	[
		"NAME:Setup1",
		"SolveType:="		, "Single",
		"Frequency:="		, "40GHz",
		"MaxDeltaS:="		, 0.01
        ,
    ])

    oModule.EditFrequencySweep("Setup1", "Freq_Sweep", 
	[
		"NAME:Freq_Sweep",
		"IsEnabled:="		, True,
		"RangeType:="		, "LinearStep",
		"RangeStart:="		, "0.1GHz",
		"RangeEnd:="		, "60GHz",
		"RangeStep:="		, "0.1GHz",])
    
    oDesign.SetDesignSettings(
	[
		"NAME:Design Settings Data",
		"Use Advanced DC Extrapolation:=", False,
		"Use Power S:="		, False,
		"Export FRTM After Simulation:=", False,
		"Export Rays After Simulation:=", False,
		"Export After Simulation:=", False,
		"Allow Material Override:=", True,
		"Calculate Lossy Dielectrics:=", True,
		"Perform Minimal validation:=", False,
		"EnabledObjects:="	, [],
		"Port Validation Settings:=", "Standard",
		"Save Adaptive support files:=", False
	], )
    oProject.Save()
    # oDesktop.CloseProject("sim_result")
    oDesktop.QuitApplication()
