from vnc_api import vnc_api
from vnc_api.vnc_api import EncapsulationPrioritiesType
import sys


def change_encap_priority(new_encap, hostname, fq_name):
    try:
        vnc_lib = vnc_api.VncApi(api_server_host=hostname)
        gr_obj = vnc_lib.global_vrouter_config_read(fq_name=fq_name)
        encap_obj = EncapsulationPrioritiesType(encapsulation=new_encap)
        gr_obj.set_encapsulation_priorities(encap_obj)
        vnc_lib.global_vrouter_config_update(gr_obj)
        return True
    except Exception as e:
        return e


my_hostname = sys.argv[1]
my_fq_name = sys.argv[2]
encaps = sys.argv[3]

result = change_encap_priority(encaps, my_hostname, my_fq_name)
print(result)
