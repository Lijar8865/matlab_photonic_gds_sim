# -*- coding: utf-8 -*-
import ScriptEnv
import os
import json
import sys


def _get_script_dir():
    try:
        return os.path.dirname(os.path.abspath(__file__))
    except NameError:
        if len(sys.argv) > 0 and sys.argv[0]:
            return os.path.dirname(os.path.abspath(sys.argv[0]))
        return os.getcwd()


CURRENT_DIR = _get_script_dir()
if CURRENT_DIR not in sys.path:
    sys.path.insert(0, CURRENT_DIR)


def _find_json_file(script_dir, file_name):
    workspace_root = os.path.dirname(os.path.dirname(script_dir))
    candidates = [
        os.path.join(script_dir, file_name),
        os.path.join(os.getcwd(), file_name),
        os.path.join(os.path.dirname(script_dir), file_name),
        os.path.join(workspace_root, file_name),
        os.path.join(workspace_root, "examples", file_name),
    ]
    for path in candidates:
        if os.path.isfile(path):
            return path
    raise IOError("Cannot find {0}. Checked: {1}".format(file_name, candidates))

# 导入工具函数模块
import hfss_utils as hu

if __name__ == "__main__":
    current_dir = CURRENT_DIR
    base_path = os.path.join(current_dir, "T_rail_TWE_GSG_base.aedt")
    ScriptEnv.Initialize("Ansoft.ElectronicsDesktop")
    oDesktop.RestoreWindow() 
    oDesktop.OpenProject(base_path)
    oProject = oDesktop.SetActiveProject("T_rail_TWE_GSG_base")
    oDesign = oProject.SetActiveDesign("HFSSDesign1")
    oEditor = oDesign.SetActiveEditor("3D Modeler")
    
    json_path = _find_json_file(current_dir, 'matlab_to_hfss.json')
    with open(json_path, 'r') as f:
        raw_data = json.load(f)
    data = hu.DotObject(raw_data)
    
    save_folder = data.save_folder
    save_dir = os.path.join(current_dir, save_folder)
    if not os.path.isdir(save_dir):
        os.makedirs(save_dir)
    
    oProject = oDesktop.SetActiveProject("T_rail_TWE_GSG_base")
    save_path = os.path.join(save_dir, "sim_result.aedt")
    oProject.SaveAs(save_path, True)
    oEditor.SetTopDownViewDirectionForActiveView("Global")
    oEditor.FitAll()
    
    # 改参数先
    hu.change_local_variable(oDesign, "Gap", "{0}um".format(data.Gap))
    hu.change_local_variable(oDesign, "W_rail", "{0}um".format(data.W_rail))
    hu.change_local_variable(oDesign, "W_T", "{0}um".format(data.W_T))
    hu.change_local_variable(oDesign, "L_rail", "{0}um".format(data.L_rail))
    hu.change_local_variable(oDesign, "period", "{0}um".format(data.period))
    hu.change_local_variable(oDesign, "L_T", "{0}um".format(data.L_T))
    hu.change_local_variable(oDesign, "W_S", "{0}um".format(data.W_S))
    hu.change_local_variable(oDesign, "W_G", "{0}um".format(data.W_G))
    hu.change_local_variable(oDesign, "L", "{0}um".format(data.L))
    hu.change_local_variable(oDesign, "Li", "{0}um".format(data.L*2))
    hu.change_local_variable(oDesign, "N_ele", "{0}".format(data.N_ele))
    hu.change_local_variable(oDesign, "W", "720um")
    hu.change_object_material(oEditor, "substrate", "silicon")
    oEditor.FitAll()
    
    # 加电极
    if data.T_flag == 1:
        hu.create_sweep_polyline(oEditor, data.T_rail_S_R, "T_rail_S_R", "gold", ("0um", "0um", "H_Au"), solve_inside=False)
        hu.create_sweep_polyline(oEditor, data.T_rail_S_L, "T_rail_S_L", "gold", ("0um", "0um", "H_Au"), solve_inside=False)
        hu.create_sweep_polyline(oEditor, data.T_rail_G_center, "T_rail_G_center", "gold", ("0um", "0um", "H_Au"), solve_inside=False)
        hu.create_sweep_polyline(oEditor, data.T_rail_G_R, "T_rail_G_R", "gold", ("0um", "0um", "H_Au"), solve_inside=False)
        hu.create_sweep_polyline(oEditor, data.T_rail_G_L, "T_rail_G_L", "gold", ("0um", "0um", "H_Au"), solve_inside=False)
    
    # 弯曲前的taper
    hu.create_sweep_polyline(oEditor, data.G_taper_in, "G_taper_in", "gold", ("0um", "0um", "H_Au"), solve_inside=False)
    hu.create_sweep_polyline(oEditor, data.G_taper_out, "G_taper_out", "gold", ("0um", "0um", "H_Au"), solve_inside=False)
    hu.create_sweep_polyline(oEditor, data.G_taper_center, "G_taper_center", "gold", ("0um", "0um", "H_Au"), solve_inside=False)
    
    # 弯曲
    hu.create_sweep_polyline(oEditor, data.Bend_G_ele, "Bend_G_ele", "gold", ("0um", "0um", "H_Au"), solve_inside=False)
    hu.create_sweep_polyline(oEditor, data.Bend_S_ele, "Bend_S_ele", "gold", ("0um", "0um", "H_Au"), solve_inside=False)
    hu.create_sweep_polyline(oEditor, data.Center_G_ele, "Center_G_ele", "gold", ("0um", "0um", "H_Au"), solve_inside=False)
    
    # 分配端口（如果需要手动分配终端，取消注释）
    hu.assign_terminal(oDesign, "S1_T1", [622], "1")
    hu.assign_terminal(oDesign, "S2_T1", [634], "2")
    
    # 更改端口坐标
    hu.change_rectangle_position(oEditor, "S1", "-W_S/2+{0}um".format(data.Disp_S/2), "-L_lump", "H_slab+H_clad+H_Au", create_index=1)
    hu.change_rectangle_position(oEditor, "S2", "-W_S/2-{0}um".format(data.Disp_S/2), "-L_lump", "H_slab+H_clad+H_Au", create_index=1)
    hu.change_rectangle_position(oEditor, "G1", "-W_G/2", "-L_lump", "H_slab+H_clad+H_Au", create_index=1)
    hu.change_rectangle_position(oEditor, "G2", "-W_G/2+{0}um".format(data.Disp_G/2), "-L_lump", "H_slab+H_clad+H_Au", create_index=1)
    hu.change_rectangle_position(oEditor, "G3", "-W_G/2", "-2*L_lump", "H_slab+H_clad+H_Au", create_index=1)
    hu.change_rectangle_position(oEditor, "G4", "-W_G/2", "-L_lump", "H_slab+H_clad+H_Au", create_index=1)
    hu.change_rectangle_position(oEditor, "G5", "-W_G/2-{0}um".format(data.Disp_G/2), "-L_lump", "H_slab+H_clad+H_Au", create_index=1)
    hu.change_rectangle_position(oEditor, "G6", "-W_G/2-{0}um".format(data.Disp_G/2), "-2*L_lump", "H_slab+H_clad+H_Au", create_index=1)

    # 更改setup
    oModule = oDesign.GetModule("AnalysisSetup")
    oModule.EditSetup("Setup1", 
        [
            "NAME:Setup1",
            "SolveType:=", "Single",
            "Frequency:=", "40GHz",
            "MaxDeltaS:=", 0.01
        ])

    oModule.EditFrequencySweep("Setup1", "Freq_Sweep", 
        [
            "NAME:Freq_Sweep",
            "IsEnabled:=", True,
            "RangeType:=", "LinearStep",
            "RangeStart:=", "0.1GHz",
            "RangeEnd:=", "60GHz",
            "RangeStep:=", "0.1GHz"
        ])
    
    oDesign.SetDesignSettings(
        [
            "NAME:Design Settings Data",
            "Use Advanced DC Extrapolation:=", False,
            "Use Power S:=", False,
            "Export FRTM After Simulation:=", False,
            "Export Rays After Simulation:=", False,
            "Export After Simulation:=", False,
            "Allow Material Override:=", True,
            "Calculate Lossy Dielectrics:=", True,
            "Perform Minimal validation:=", False,
            "EnabledObjects:=", [],
            "Port Validation Settings:=", "Standard",
            "Save Adaptive support files:=", False
        ])
    oProject.Save()
    # oDesktop.QuitApplication()
